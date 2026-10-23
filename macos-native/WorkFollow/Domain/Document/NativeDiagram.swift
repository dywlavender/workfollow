import Foundation

/// Source and preview are one document value, including persistence and undo.
/// A drawing must remain editable after the document is closed or exported.
struct NativeDiagram: Equatable, Codable, Identifiable {
    var id = UUID()
    var title = "流程图"
    var xml: String
    var previewPNG: Data

    static let emptyXML = """
    <mxfile host="WorkFollow"><diagram name="第 1 页"><mxGraphModel grid="1" gridSize="10" page="0"><root><mxCell id="0"/><mxCell id="1" parent="0"/></root></mxGraphModel></diagram></mxfile>
    """
}
