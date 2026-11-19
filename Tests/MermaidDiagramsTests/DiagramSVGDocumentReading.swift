/**
 * File: DiagramSVGDocumentReading.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Reads an SVG document back with Foundation's XML parser: whether it is well formed, its elements with
 *              their attributes, and the text of each text element.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import Foundation

/// An SVG document read back by `XMLParser`: nil when it is not well-formed XML.
final class DiagramSVGDocumentReading: NSObject, XMLParserDelegate {
    struct Element {
        let name: String
        let attributes: [String: String]
        var text = ""
    }

    private(set) var elements: [Element] = []
    private var openTextIndex: Int?

    static func read(_ document: String) -> DiagramSVGDocumentReading? {
        let reading = DiagramSVGDocumentReading()
        let parser = XMLParser(data: Data(document.utf8))
        parser.delegate = reading
        return parser.parse() ? reading : nil
    }

    func elements(named name: String) -> [Element] {
        elements.filter { element in element.name == name }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        elements.append(Element(name: elementName, attributes: attributeDict))
        if elementName == "text" { openTextIndex = elements.count - 1 }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "text" { openTextIndex = nil }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard let openTextIndex else { return }
        elements[openTextIndex].text += string
    }
}
