import Foundation

/// A simple node representing an XML element with attributes, text value, and children.
final class XMLNode {
    let name: String
    let attributes: [String: String]
    var value: String = ""
    var children: [XMLNode] = []
    
    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }
    
    func child(named name: String) -> XMLNode? {
        children.first { $0.name.lowercased() == name.lowercased() }
    }
    
    func children(named name: String) -> [XMLNode] {
        children.filter { $0.name.lowercased() == name.lowercased() }
    }
}

/// A lightweight XML parser delegate that parses files into a tree of XMLNodes.
final class TinyXMLParser: NSObject, XMLParserDelegate {
    var root: XMLNode?
    private var stack: [XMLNode] = []
    private var currentValue = ""
    
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let node = XMLNode(name: elementName, attributes: attributeDict)
        if let parent = stack.last {
            parent.children.append(node)
        } else {
            root = node
        }
        stack.append(node)
        currentValue = ""
    }
    
    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        if let last = stack.last {
            // Trim whitespace and newlines from element text
            last.value = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !stack.isEmpty {
            stack.removeLast()
        }
        currentValue = ""
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string
    }
}

/// Convenience helper to parse XML data into an XMLNode tree.
func parseXML(data: Data) -> XMLNode? {
    let parser = XMLParser(data: data)
    let delegate = TinyXMLParser()
    parser.delegate = delegate
    guard parser.parse() else { return nil }
    return delegate.root
}
