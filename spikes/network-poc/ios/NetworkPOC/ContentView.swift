import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Buttons Network POC")
            .padding()
            .onAppear {
                var ping = Ping()
                ping.text = "codegen check"
                print(ping)
            }
    }
}

#Preview {
    ContentView()
}
