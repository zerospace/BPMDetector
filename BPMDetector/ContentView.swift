//
//  ContentView.swift
//  BPMDetector
//
//  Created by Oleksandr Fedko on 25.06.2024.
//

import SwiftUI
import AVFAudio
import AVFoundation
import Charts

struct ContentView: View {
    @State private var bpm: Float = 0
    @State private var time: Double = 0
    @State private var isPlaying: Bool = false
    @State private var artist: String? = nil
    @State private var filename: String? = nil
    @State private var openFile: Bool = false
    
    @State private var pcmBuffer: AVAudioPCMBuffer?
    private let player = AVAudioPlayerNode()
    private let engine = AVAudioEngine()
    private let detector = BPMDetector()
    
    private struct ChartItem: Identifiable {
        var id = UUID()
        let x: Float
        let y: Float
    }
    @State private var histogram1 = [ChartItem]()
    @State private var histogram2 = [ChartItem]()
    
    init() {
        do {
            self.engine.attach(self.player)
            self.engine.connect(self.player, to: self.engine.mainMixerNode, format: nil)
            try self.engine.start()
        }
        catch { print(error.localizedDescription) }
    }
    
    var body: some View {
        VStack {
            Button {
                openFile = true
            } label: {
                Image(systemName: "music.note.list")
                Text("Open File")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(.black)
            
            HStack {
                Button {
                    guard pcmBuffer != nil else { return }
                    if isPlaying {
                        player.pause()
                    }
                    else {
                        player.play()
                    }
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .tint(.white)
                }
                .frame(width: 50.0, height: 50.0)
                .background(.blue)
                .clipShape(Circle())
                
                VStack {
                    Text(artist ?? "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.caption)
                    
                    Text(filename ?? "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.title3)
                }
            }
            
            Group {
                Text("BPM: ") + Text(String(format: "%.2f", bpm))
                Text("Elapsed Time: ") + Text(String(format: "%.2f sec", time))
            }
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)

            Chart(histogram1) { item in
                LineMark(x: .value("Beat", item.x),
                         y: .value("Occurrence", item.y)
                )
                .foregroundStyle(.blue)
            }
            .chartXAxisLabel("Beat interval (seconds)")
            .chartYAxisLabel("Occurrence")
            
            Chart(histogram2) { item in
                LineMark(x: .value("Beat", item.x),
                         y: .value("Amplitude", item.y)
                )
                .foregroundStyle(.blue)
            }
            .chartXAxisLabel("Beat interval (seconds)")
            .chartYAxisLabel("Amplitude")
            
            Spacer()
            
            Button {
                if let buffer = pcmBuffer {
                    let start = DispatchTime.now()
                    let data = buffer.floatChannelData![0]
                    let array = Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
                    let bpm =  detector.compute(in: array, sampleRate: Float(buffer.format.sampleRate))
                    let end = DispatchTime.now()
                    time = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
                    
                    self.bpm = bpm.value
                    if let debug = bpm.debug {
                        self.histogram1 = histogram(for: debug.occurrence)
                        self.histogram2 = histogram(for: debug.amplitude)
                    }
                }
            } label: {
                Text("Extract Tempo")
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.black)
            }
            .frame(height: 56.0)
            .background {
                RoundedRectangle(cornerRadius: 100.0)
                    .stroke(.black, style: StrokeStyle(lineWidth: 3.0))
            }
            .clipShape(RoundedRectangle(cornerRadius: 100.0))


        }
        .padding()
        .fileImporter(isPresented: $openFile, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url):
                isPlaying = false
                player.stop()
                bpm = 0
                time = 0
                histogram1.removeAll()
                histogram2.removeAll()
                
                Task { @MainActor in
                    do {
                        let asset = AVAsset(url: url)
                        let metadata = try await asset.load(.metadata)
                        self.filename = try await AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierTitle).first?.load(.stringValue)
                        self.artist = try await AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtist).first?.load(.stringValue)
                    }
                    catch { print(error.localizedDescription) }
                }
                
                do {
                    let file = try AVAudioFile(forReading: url)
                    let format = file.processingFormat
                    let frameCount = UInt32(file.length)
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                        print("Can't read PCM buffer")
                        return
                    }
                    try file.read(into: buffer)
                    self.pcmBuffer = buffer
                    self.player.scheduleFile(file, at: nil)
                }
                catch { print(error.localizedDescription) }
            case .failure(let error):
                print(error.localizedDescription)
            }
        }
    }
    
    private func histogram(for peaks: [Float]) -> [ChartItem] {
        var items = [ChartItem]()
        guard let midSR = pcmBuffer?.format.sampleRate else { return items }
        var i = 0
        let count = peaks.count
        while i<count {
            items.append(ChartItem(x: Float(i)/Float(count), y: peaks[i]))
            i += 1
        }
        return items
    }
}

extension AVMetadataItem: @unchecked Sendable { }
