import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text("ぷにょ")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

#Preview {
    ContentView()
}
