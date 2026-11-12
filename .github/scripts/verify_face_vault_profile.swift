// Read-only build gate. No SecItem, LAContext, broker or user-data operation.
// security(1) cms -D only decodes; it does not establish signature validity.
import Foundation
import Security
import CryptoKit
import Darwin

func require(_ condition: @autoclosure () -> Bool) {
    if !condition() {
        fputs("FAIL: provisioning CMS signature/signer/trust validation refused\n", stderr)
        exit(1)
    }
}

require(CommandLine.arguments.count == 2)
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
require(data.count > 0 && data.count <= 1_000_000)
var decoder: CMSDecoder?
require(CMSDecoderCreate(&decoder) == errSecSuccess)
require(decoder != nil)
let update = data.withUnsafeBytes { CMSDecoderUpdateMessage(decoder!, $0.baseAddress!, $0.count) }
require(update == errSecSuccess && CMSDecoderFinalizeMessage(decoder!) == errSecSuccess)
var count = 0
require(CMSDecoderGetNumSigners(decoder!, &count) == errSecSuccess && count == 1)
var status = CMSSignerStatus(rawValue: 0)!
var trust: SecTrust?
var certificateStatus: OSStatus = errSecSuccess
require(CMSDecoderCopySignerStatus(decoder!, 0, SecPolicyCreateBasicX509(), false,
    &status, &trust, &certificateStatus) == errSecSuccess)
require(status == .valid && trust != nil)
require(SecTrustSetNetworkFetchAllowed(trust!, false) == errSecSuccess)
require(SecTrustEvaluateWithError(trust!, nil))
var signer: SecCertificate?
require(CMSDecoderCopySignerCert(decoder!, 0, &signer) == errSecSuccess && signer != nil)
let digest = SHA256.hash(data: SecCertificateCopyData(signer!) as Data).map { String(format: "%02x", $0) }.joined()
// Exact Mac OS X Provisioning Profile Signing certificate in the profile
// fetched by authenticated Xcode for this prototype. This pin is independent of
// the app development certificate; a different Apple signer needs review.
require(digest == "0884fc026365e14a91cec77583b5b4ae041be49bc990e74f4a15e2b42b50dc55")
require(SecCertificateCopySubjectSummary(signer!) as String? == "Mac OS X Provisioning Profile Signing")
var content: CFData?
require(CMSDecoderCopyContent(decoder!, &content) == errSecSuccess && content != nil)
FileHandle.standardOutput.write(content! as Data)
