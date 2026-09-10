// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Maps original web addresses to the immutable files in one game library entry.
struct WebRouting {
    let record: WebImportRecord
    let origin: URL
    let isHTML: Bool
    var root: URL { isHTML ? origin : origin.appendingPathComponent("game",isDirectory:true) }
    var pairs: [[String]] {
        record.files.flatMap { file in file.urls.map { [$0.absoluteString,root.appendingPathComponent(file.path).absoluteString] } }
    }
    var prefixes: [[String]] {
        var values: [String:String] = [:]
        for url in record.files.flatMap(\.urls) + [record.entryURL,record.page] + Array(record.documentBases.values) {
            guard var parts = URLComponents(url:url,resolvingAgainstBaseURL:true) else { continue }
            parts.path = "/"; parts.query = nil; parts.fragment = nil
            if let remote = parts.url { values[remote.absoluteString] = root.appendingPathComponent(WebImportRecord.namespace(url),isDirectory:true).absoluteString }
        }
        return values.sorted { $0.key < $1.key }.map { [$0.key,$0.value] }
    }
    var options: [String:Any] { ["webFiles":pairs,"webOrigins":prefixes,"webFallback":root.appendingPathComponent("unavailable",isDirectory:true).absoluteString] }
    func local(_ remote: URL) -> URL {
        if let file = record.files.first(where:{ $0.urls.contains(remote) }) { return root.appendingPathComponent(file.path) }
        let pair = prefixes.first { remote.absoluteString.hasPrefix($0[0]) }
        if let pair, let url = URL(string:pair[1] + remote.absoluteString.dropFirst(pair[0].count)) { return url }
        return root.appendingPathComponent(WebImportRecord.path(remote))
    }
    func path(for request: URL) -> String? {
        let requestedPath = String(request.path.dropFirst(isHTML ? 1 : 6))
        if record.files.contains(where:{ $0.path == requestedPath }), request.query == nil { return requestedPath }
        var remote: URL?
        if let pair = prefixes.first(where:{ request.absoluteString.hasPrefix($0[1]) }) {
            remote = URL(string:pair[0] + request.absoluteString.dropFirst(pair[1].count))
        } else if isHTML, !request.path.hasPrefix("/web/") {
            // Root-relative URLs generated at runtime still belong to the original site.
            var parts = URLComponents(url:record.entryURL,resolvingAgainstBaseURL:true)
            parts?.path = request.path; parts?.percentEncodedQuery = URLComponents(url:request,resolvingAgainstBaseURL:true)?.percentEncodedQuery
            remote = parts?.url
        }
        if let remote, let file = record.files.first(where:{ $0.urls.contains(remote) }) { return file.path }
        return nil
    }
    func text(_ source: String, path: String, mime: String) -> String {
        guard let file = record.files.first(where:{ $0.path == path }), let original = file.urls.last else { return source }
        var result = source
        // Exact mappings precede origin mappings so query variants retain their own files.
        for pair in pairs.sorted(by:{ $0[0].count > $1[0].count }) {
            result = result.replacingOccurrences(of:pair[0],with:pair[1])
            result = result.replacingOccurrences(of:pair[0].replacingOccurrences(of:"/",with:"\\/"),with:pair[1].replacingOccurrences(of:"/",with:"\\/"))
        }
        for pair in prefixes {
            result = result.replacingOccurrences(of:pair[0],with:pair[1])
            let withoutScheme = "//" + pair[0].split(separator:"/",omittingEmptySubsequences:true).dropFirst().joined(separator:"/") + "/"
            result = result.replacingOccurrences(of:"\"" + withoutScheme,with:"\"" + pair[1]).replacingOccurrences(of:"'" + withoutScheme,with:"'" + pair[1])
        }
        let base = record.documentBases[path] ?? original
        let isPage = mime == "text/html" || ["html","htm"].contains((path as NSString).pathExtension.lowercased())
        // Rewrite HTML attributes, never arbitrary JS string fragments such as
        // language + "/strings.json". Runtime requests go through the URL mapper.
        if isPage {
            for tag in WebPage.matches(#"<[A-Za-z][^>]{0,32768}>"#,result) {
                var replacement = tag[0]
                for match in WebPage.matches(#"(\b(?:src|href|poster|data)\s*=\s*)(['"])(/[^'"\r\n]{1,8192})\2"#,tag[0]) {
                    if let url = WebAddress.resolve(match[3],from:base) { replacement = replacement.replacingOccurrences(of:match[0],with:match[1] + match[2] + local(url).absoluteString + match[2]) }
                }
                for match in WebPage.matches(#"(\b(?:src|href|poster|data)\s*=\s*)(/[^\s>'"]+)"#,tag[0]) {
                    if let url = WebAddress.resolve(match[2],from:base) { replacement = replacement.replacingOccurrences(of:match[0],with:match[1] + "\"" + local(url).absoluteString + "\"") }
                }
                result = result.replacingOccurrences(of:tag[0],with:replacement)
            }
        }
        if mime == "text/css" || (path as NSString).pathExtension.lowercased() == "css" {
            for match in WebPage.matches(#"url\(\s*['"]?(/[^\s\)'\"]+)['"]?\s*\)"#,result) {
                if let url = WebAddress.resolve(match[1],from:base) { result = result.replacingOccurrences(of:match[0],with:"url(\"" + local(url).absoluteString + "\")") }
            }
        }
        if isPage {
            result = result.replacingOccurrences(of:#"(?i)<base\b[^>]*>"#,with:"",options:.regularExpression)
            let localBase = local(base).absoluteString.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"\"",with:"&quot;")
            let tag = "<base href=\"" + localBase + "\">"
            if let head = result.range(of:#"(?i)<head\b[^>]*>"#,options:.regularExpression) { result.insert(contentsOf:tag,at:head.upperBound) }
            else { result = tag + result }
        }
        return result
    }
    var script: String {
        guard let data = try? JSONSerialization.data(withJSONObject:options,options:[.sortedKeys]) else { return "" }
        return """
        (()=>{
          const options=\(String(decoding:data,as:UTF8.self));
          const files=new Map(options.webFiles);
          const mapURL=value=>{try{
            const raw=String(value),url=new URL(raw,document.baseURI);
            const fragment=url.hash;url.hash='';
            if(files.has(url.href))return files.get(url.href)+fragment;
            if(url.protocol==='http:'||url.protocol==='https:'){
              const pair=options.webOrigins.find(p=>url.href.startsWith(p[0]));
              return (pair?pair[1]+url.href.slice(pair[0].length):options.webFallback+encodeURIComponent(url.href))+fragment;
            }return raw;
          }catch{return value;}};
          window.flashbackMapURL=mapURL;
          const fetch=window.fetch;
          window.fetch=function(input,init){
            if(input instanceof Request){const next=mapURL(input.url);if(next!==input.url)input=new Request(next,input);}
            else input=mapURL(input);
            return fetch.call(this,input,init);
          };
          const open=XMLHttpRequest.prototype.open;
          XMLHttpRequest.prototype.open=function(method,url,...rest){return open.call(this,method,mapURL(url),...rest);};
          for(const name of ['Worker','SharedWorker'])if(window[name]){
            window[name]=new Proxy(window[name],{construct(target,args,newTarget){args[0]=mapURL(args[0]);return Reflect.construct(target,args,newTarget);}});
          }
        })();
        """
    }
}
