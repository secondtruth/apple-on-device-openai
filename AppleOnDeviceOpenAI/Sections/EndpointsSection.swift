import SwiftUI

struct EndpointsSection: View {
    var body: some View {
        GroupBox("All Available Endpoints") {
            VStack(alignment: .leading, spacing: 8) {
                EndpointRow(method: "GET", path: "/health", description: "Health check")
                EndpointRow(method: "GET", path: "/status", description: "Model status")
                EndpointRow(method: "GET", path: "/v1/models", description: "List models")
                EndpointRow(method: "POST", path: "/v1/chat/completions", description: "Chat completions")
            }
        }
    }
}
