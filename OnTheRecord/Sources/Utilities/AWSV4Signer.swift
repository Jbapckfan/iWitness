import Foundation
import CryptoKit

/// Helper for signing requests with AWS Signature V4
/// Used for S3-compatible services (Cloudflare R2, AWS S3, Backblaze B2)
enum AWSV4Signer {
    
    struct SigningKeys {
        let accessKey: String
        let secretKey: String
        let region: String
        let service: String
    }
    
    /// Signs a URLRequest using AWS Signature V4
    /// - Parameters:
    ///   - request: The request to sign (must have URL and HTTPMethod)
    ///   - keys: Credentials and scope
    ///   - payloadHash: Pre-computed SHA256 hash of the body (default: empty string hash)
    ///   - date: Date to sign with (default: current date)
    /// - Returns: A new URLRequest with Authorization and x-amz-date headers
    static func sign(
        request: URLRequest,
        keys: SigningKeys,
        payloadHash: String? = nil,
        date: Date = Date()
    ) -> URLRequest {
        var signedRequest = request
        
        // 1. Format Dates
        let iso8601Formatter = DateFormatter()
        iso8601Formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        iso8601Formatter.timeZone = TimeZone(identifier: "UTC")
        let amzDate = iso8601Formatter.string(from: date)
        
        let dateKeyFormatter = DateFormatter()
        dateKeyFormatter.dateFormat = "yyyyMMdd"
        dateKeyFormatter.timeZone = TimeZone(identifier: "UTC")
        let dateStamp = dateKeyFormatter.string(from: date)
        
        // 2. Add Basic Headers
        guard let host = request.url?.host else { return request }
        
        signedRequest.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        signedRequest.setValue(host, forHTTPHeaderField: "Host")
        
        // Default payload hash (SHA256 of empty string)
        let contentHash = payloadHash ?? "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        signedRequest.setValue(contentHash, forHTTPHeaderField: "x-amz-content-sha256")
        
        // 3. Canonical Request
        let canonicalUri = request.url?.path ?? "/"
        let canonicalQueryString = "" // For now, we assume no query params for simple PUTs
        
        // Headers must be lowercased and sorted
        let canonicalHeaders = """
        host:\(host)
        x-amz-content-sha256:\(contentHash)
        x-amz-date:\(amzDate)
        
        """
        
        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        let method = request.httpMethod ?? "GET"
        
        let canonicalRequest = """
        \(method)
        \(canonicalUri)
        \(canonicalQueryString)
        \(canonicalHeaders)
        \(signedHeaders)
        \(contentHash)
        """
        
        // 4. String to Sign
        let credentialScope = "\(dateStamp)/\(keys.region)/\(keys.service)/aws4_request"
        let algorithm = "AWS4-HMAC-SHA256"
        let canonicalRequestHash = SHA256.hash(data: canonicalRequest.data(using: .utf8)!).compactMap { String(format: "%02x", $0) }.joined()
        
        let stringToSign = """
        \(algorithm)
        \(amzDate)
        \(credentialScope)
        \(canonicalRequestHash)
        """
        
        // 5. Signature Calculation
        let dateKey = hmac(string: dateStamp, key: "AWS4\(keys.secretKey)".data(using: .utf8)!)
        let dateRegionKey = hmac(string: keys.region, key: dateKey)
        let dateRegionServiceKey = hmac(string: keys.service, key: dateRegionKey)
        let signingKey = hmac(string: "aws4_request", key: dateRegionServiceKey)
        
        let signature = hmac(string: stringToSign, key: signingKey).compactMap { String(format: "%02x", $0) }.joined()
        
        // 6. Authorization Header
        let authHeader = "\(algorithm) Credential=\(keys.accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        
        signedRequest.setValue(authHeader, forHTTPHeaderField: "Authorization")
        
        return signedRequest
    }
    
    // Helper HMAC
    private static func hmac(string: String, key: Data) -> Data {
        let keySym = SymmetricKey(data: key)
        let code = HMAC<SHA256>.authenticationCode(for: string.data(using: .utf8)!, using: keySym)
        return Data(code)
    }
}
