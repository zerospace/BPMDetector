//
//  Wavelet.swift
//  BPMDetector
//
//  Created by Oleksandr Fedko on 25.06.2024.
//

import Foundation
import Accelerate

struct Wavelet {
    enum Daubechies: Int {
        case db1, db2, db3, db4, db5
        
        var coefficients: [Float] {
            switch self {
            case .db1:
                return [7.071067811865475244008443621048490392848359376884740365883398e-01,
                        7.071067811865475244008443621048490392848359376884740365883398e-01]
            case .db2:
                return [4.829629131445341433748715998644486838169524195042022752011715e-01,
                        8.365163037378079055752937809168732034593703883484392934953414e-01,
                        2.241438680420133810259727622404003554678835181842717613871683e-01,
                       -1.294095225512603811744494188120241641745344506599652569070016e-01]
            case .db3:
                return [3.326705529500826159985115891390056300129233992450683597084705e-01,
                        8.068915093110925764944936040887134905192973949948236181650920e-01,
                        4.598775021184915700951519421476167208081101774314923066433867e-01,
                       -1.350110200102545886963899066993744805622198452237811919756862e-01,
                       -8.544127388202666169281916918177331153619763898808662976351748e-02,
                        3.522629188570953660274066471551002932775838791743161039893406e-02]
            case .db4:
                return [2.303778133088965008632911830440708500016152482483092977910968e-01,
                        7.148465705529156470899219552739926037076084010993081758450110e-01,
                        6.308807679298589078817163383006152202032229226771951174057473e-01,
                       -2.798376941685985421141374718007538541198732022449175284003358e-02,
                       -1.870348117190930840795706727890814195845441743745800912057770e-01,
                        3.084138183556076362721936253495905017031482172003403341821219e-02,
                        3.288301166688519973540751354924438866454194113754971259727278e-02,
                       -1.059740178506903210488320852402722918109996490637641983484974e-02]
            case .db5:
                return [1.601023979741929144807237480204207336505441246250578327725699e-01,
                        6.038292697971896705401193065250621075074221631016986987969283e-01,
                        7.243085284377729277280712441022186407687562182320073725767335e-01,
                        1.384281459013207315053971463390246973141057911739561022694652e-01,
                       -2.422948870663820318625713794746163619914908080626185983913726e-01,
                       -3.224486958463837464847975506213492831356498416379847225434268e-02,
                        7.757149384004571352313048938860181980623099452012527983210146e-02,
                       -6.241490212798274274190519112920192970763557165687607323417435e-03,
                       -1.258075199908199946850973993177579294920459162609785020169232e-02,
                        3.335725285473771277998183415817355747636524742305315099706428e-03]
            }
        }
    }
    
    func transform(_ input: [Float], wavelet: Daubechies) -> ([Float], [Float]) {
        let N = input.count
        var lowPassResult = [Float](repeating: 0.0, count: N)
        var highPassResult = [Float](repeating: 0.0, count: N)
        
        let highPassFilter = wavelet.coefficients
        let filterLength = highPassFilter.count
        let lowPassFilter = wavelet.coefficients.reversed().enumerated().map({ $0.0 % 2 != 0 ? -$0.1 : $0.1 })
        let pad = input + Array(input[..<(filterLength>>1)])
        
        // Convolve input with low-pass filter
        vDSP_conv(pad, 1, lowPassFilter, 1, &lowPassResult, 1, vDSP_Length(N), vDSP_Length(filterLength))
        lowPassResult = vDSP.downsample(lowPassResult, decimationFactor: 2, filter: [1])

        // Convolve input with high-pass filter
        vDSP_conv(pad, 1, highPassFilter, 1, &highPassResult, 1, vDSP_Length(N), vDSP_Length(filterLength))
        highPassResult = vDSP.downsample(highPassResult, decimationFactor: 2, filter: [1])

        return (highPassResult, lowPassResult)
    }
}
