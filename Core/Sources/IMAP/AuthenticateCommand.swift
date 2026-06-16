// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import NIOCore
import NIOIMAP

// Authenticate to an IMAP server using SASL XOAUTH2 (OAuth2 bearer token).
// https://developers.google.com/workspace/gmail/imap/xoauth2-protocol
struct AuthenticateCommand: IMAPCommand {
    let username: String
    let token: String

    // MARK: IMAPCommand
    typealias Result = [Capability]
    typealias Handler = AuthenticateHandler

    var name: String { "authenticate XOAUTH2 \"\(username)\"" }

    func tagged(_ tag: String) -> NIOIMAPCore.TaggedCommand {
        // SASL XOAUTH2 initial response: "user=<email>^Aauth=Bearer <token>^A^A" (^A = Ctrl+A / 0x01).
        // NIOIMAP base64-encodes the InitialResponse, so the raw bytes are passed here.
        let saslString = "user=\(username)\u{01}auth=Bearer \(token)\u{01}\u{01}"
        let initialResponse = InitialResponse(ByteBuffer(string: saslString))
        return TaggedCommand(
            tag: tag,
            command: .authenticate(mechanism: AuthenticationMechanism("XOAUTH2"), initialResponse: initialResponse)
        )
    }
}

// Handle the XOAUTH2 exchange. On success the server returns a tagged OK (with optional
// capabilities). On a bad token Gmail sends a base64 error challenge before the tagged NO — treat
// that challenge as a fast authentication failure instead of waiting for the command to time out.
class AuthenticateHandler: IMAPCommandHandler, @unchecked Sendable {

    // MARK: IMAPCommandHandler
    typealias InboundIn = Response
    typealias InboundOut = Response
    typealias Result = [Capability]

    var capabilities: Result = []
    var clientBug: String? = nil
    let promise: EventLoopPromise<Result>
    let tag: String

    required init(tag: String, promise: EventLoopPromise<Result>) {
        self.promise = promise
        self.tag = tag
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let response: Response = unwrapInboundIn(data)
        clientBug = response.clientBug
        switch response {
        case .tagged(let taggedResponse):
            switch taggedResponse.state {
            case .bad(let text), .no(let text):
                promise.fail(IMAPError.authenticationFailed(text.text))
            case .ok:
                promise.succeed(capabilities)
            }
        case .untagged(let payload):
            if case .capabilityData(let capabilities) = payload {
                self.capabilities = capabilities.map { Capability($0) }
            }
        case .authenticationChallenge(let buffer):
            // The server rejected the initial response (e.g. expired/invalid token) and is
            // challenging for more SASL data. Fail fast rather than stall until the timeout.
            let detail: String = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) ?? "XOAUTH2 rejected"
            promise.fail(IMAPError.authenticationFailed(detail))
        default:
            break
        }
        context.fireChannelRead(data)
    }
}
