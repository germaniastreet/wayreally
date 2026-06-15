import SwiftUI

struct AudioCaptureScreen: View { @State private var isRecording = true; @State private var elapsedSeconds = 1634
    var body: some View { NavigationStack { ZStack { SecondTheme.background.ignoresSafeArea(); ScrollView { VStack(spacing:16) { ScreenHeader(title:"Audio Capture", subtitle:"Capture high-quality audio for analysis"); AppCard(title:isRecording ? "Recording" : "Paused") { VStack(spacing:18) { Text(timerText).font(.system(size:44, weight:.bold, design:.rounded)); MiniLineChart(values:SampleData.biometricSamples.compactMap{$0.heartRate}, color:SecondTheme.heartRate).frame(height:82); HStack { SignalBadge(icon:"mic", title:"Input", value:"Built-in", color:SecondTheme.primaryText); Spacer(); SignalBadge(icon:"waveform", title:"Level", value:"Good", color:SecondTheme.respiration) }; HStack(spacing:36) { CaptureButton(icon:isRecording ? "pause" : "play", label:isRecording ? "Pause" : "Resume", color:SecondTheme.background) { isRecording.toggle() }; CaptureButton(icon:"stop.fill", label:"Stop", color:Color.red.opacity(0.9)) { isRecording = false }; CaptureButton(icon:"bookmark", label:"Marker", color:SecondTheme.background) {} } } }.padding(.horizontal); AppCard(title:"Session Info") { HStack { MetricColumn(title:"Quality", value:"High"); Divider(); MetricColumn(title:"Format", value:"WAV"); Divider(); MetricColumn(title:"Estimated Size", value:"~32 MB/hr") } }.padding(.horizontal); AppCard(title:"Live Audio Levels") { HStack(alignment:.bottom, spacing:7) { ForEach(0..<28, id:\.self) { i in RoundedRectangle(cornerRadius:4).fill(levelColor(i)).frame(width:9, height:CGFloat(22+(i%7)*5)) } } }.padding(.horizontal) }.padding(.bottom,24) } } } }
    private var timerText:String { String(format:"00:%02d:%02d", elapsedSeconds/60, elapsedSeconds%60) }
    private func levelColor(_ i:Int)->Color { i < 18 ? SecondTheme.respiration : (i < 23 ? SecondTheme.gold : SecondTheme.border.opacity(0.6)) }
}
struct CaptureButton: View { let icon:String; let label:String; let color:Color; let action:()->Void
    var body: some View { VStack(spacing:8) { Button(action:action) { Image(systemName:icon).font(.title2).foregroundStyle(label == "Stop" ? .white : SecondTheme.primaryText).frame(width:70,height:70).background(color).clipShape(Circle()) }; Text(label).font(.caption) } }
}
struct MetricColumn: View { let title:String; let value:String
    var body: some View { VStack(spacing:4) { Text(title).font(.caption).foregroundStyle(SecondTheme.secondaryText); Text(value).font(.headline) }.frame(maxWidth:.infinity) }
}
