// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import EmailAddress
import NIOCore
import NIOSSL

final class SendHandler: ChannelInboundHandler, @unchecked Sendable {
    let email: Email
    let recipient: EmailAddress
    let server: Server

    init(_ email: Email, recipient: EmailAddress?, server: Server, done: EventLoopPromise<Void>) {
        self.email = email
        self.recipient = recipient ?? email.recipients.first ?? ""
        self.server = server
        self.done = done
        if self.recipient.value.isEmpty {
            expect = .error(SMTPError.emailRecipientNotFound)
        }
    }

    private enum Expect {
        case initialMessageFromServer
        case okForHello
        case okForStartTLS
        case tlsHandlerToBeAdded
        case okForAuthBegin
        case okAfterXOAuth2
        case okAfterUsername
        case okAfterPassword
        case okAfterMailFrom
        case okAfterRecipient
        case okAfterData
        case okAfterTransferData
        case okAfterQuit
        case error(Error)
        case nothing
    }

    private let done: EventLoopPromise<Void>
    private var context: ChannelHandlerContext?

    private var expect: Expect = .initialMessageFromServer {
        didSet {
            guard case .error(let error) = expect else { return }
            done.fail(error)
        }
    }

    private func send(context: ChannelHandlerContext, command: Request) {
        context.writeAndFlush(wrapOutboundOut(command)).cascadeFailure(to: done)
    }

    private func sendAuth() {
        @Sendable func send() {
            guard let context else { return }
            switch server.authentication {
            case .oAuth2:
                // Single-step SASL XOAUTH2: the bearer token travels with the AUTH command.
                self.send(context: context, command: .authXOAuth2(username: server.username, token: server.password))
                expect = .okAfterXOAuth2
            case .password:
                self.send(context: context, command: .authLogin)
                expect = .okForAuthBegin
            }
        }

        switch server.connectionSecurity {
        case .startTLS, .tls:
            if let context {
                context.channel.pipeline.handler(type: NIOSSLClientHandler.self).map { _ in
                    send()  // SSL handler present in pipeline
                }.whenFailure { error in
                    guard self.server.connectionSecurity == .tls else { return }
                    self.expect = .error(error)
                }
            } else {
                expect = .error(SMTPError.requiredTLSNotConfigured)
            }
        case .none:
            send()  // Authenticate in plain text
        }
        self.context = nil
    }

    // MARK: ChannelInboundHandler
    typealias OutboundIn = Email
    typealias OutboundOut = Request
    typealias InboundIn = Response

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .error(let error):
            expect = .error(SMTPError.response(error))
        case .ok(let code, _):
            switch expect {
            case .initialMessageFromServer:
                send(context: context, command: .hello(server.hostname))
                expect = .okForHello
            case .okForHello:
                switch server.connectionSecurity {
                case .startTLS:
                    send(context: context, command: .startTLS)
                    expect = .okForStartTLS
                case .tls, .none:
                    self.context = context
                    sendAuth()
                }
            case .okForStartTLS:
                expect = .tlsHandlerToBeAdded
                self.context = context
                context.channel.eventLoop.makeCompletedFuture {
                    try context.channel.pipeline.syncOperations.addHandler(
                        try NIOSSLClientHandler(context: .ssl, serverHostname: server.hostname),
                        position: .first
                    )
                }.whenComplete { result in
                    switch self.expect {
                    case .tlsHandlerToBeAdded:
                        switch result {
                        case .failure(let error):
                            self.expect = .error(error)
                        case .success:
                            self.sendAuth()
                        }
                        break
                    default:
                        self.expect = .error(SMTPError.requiredTLSNotConfigured)
                    }
                }
            case .tlsHandlerToBeAdded:
                fatalError("SMTP.SendHandler.channelRead(context:data:) before TLS handler added to pipeline")
            case .okAfterXOAuth2:
                // Gmail replies 235 on success, or a 334 base64 error-challenge when the token is
                // bad/expired. Treat any non-2xx as an auth failure and fail fast (the caller can
                // refresh the token and retry) rather than continuing the SASL exchange.
                if code < 300 {
                    send(context: context, command: .mailFrom(email.sender))
                    expect = .okAfterMailFrom
                } else {
                    expect = .error(SMTPError.authenticationFailed)
                }
            case .okForAuthBegin:
                send(context: context, command: .authUser(server.username))
                expect = .okAfterUsername
            case .okAfterUsername:
                send(context: context, command: .authPassword(server.password))
                expect = .okAfterPassword
            case .okAfterPassword:
                send(context: context, command: .mailFrom(email.sender))
                expect = .okAfterMailFrom
            case .okAfterMailFrom:
                send(context: context, command: .recipient(recipient))
                expect = .okAfterRecipient
            case .okAfterRecipient:
                send(context: context, command: .data)
                expect = .okAfterData
            case .okAfterData:
                send(context: context, command: .transferData(email))
                expect = .okAfterTransferData
            case .okAfterTransferData:
                send(context: context, command: .quit)
                expect = .okAfterQuit
            case .okAfterQuit:
                done.succeed()
                context.close(promise: nil)
                expect = .nothing
            case .error(let error):
                fatalError("SMTP.SendHandler.channelRead(context:data:) after error: \(error)")
            case .nothing:
                break
            }
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        expect = .error(SMTPError.remoteConnectionClosed)
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        expect = .error(error)
        context.close(promise: nil)
    }
}

private extension NIOSSLContext {
    static var ssl: Self { try! Self(configuration: .makeClientConfiguration()) }
}
