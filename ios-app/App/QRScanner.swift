import SwiftUI
import AVFoundation

struct QRScanner:UIViewControllerRepresentable{
    let onCode:(String)->Void;let onError:(String)->Void
    func makeUIViewController(context:Context)->ScannerController{let controller=ScannerController();controller.onCode=onCode;controller.onError=onError;return controller}
    func updateUIViewController(_ controller:ScannerController,context:Context){}
    static func dismantleUIViewController(_ controller:ScannerController,coordinator:()){controller.stop()}
}
final class ScannerController:UIViewController,AVCaptureMetadataOutputObjectsDelegate{
    var onCode:((String)->Void)?;var onError:((String)->Void)?
    private let capture=AVCaptureSession();private let queue=DispatchQueue(label:"linedraw.camera");private var preview:AVCaptureVideoPreviewLayer?;private var finished=false
    override func viewDidLoad(){super.viewDidLoad();view.backgroundColor = .black
        AVCaptureDevice.requestAccess(for:.video){[weak self] granted in DispatchQueue.main.async{guard let self else{return};if granted{self.configure()}else{self.onError?("請在系統設定允許相機，或貼上 Mac 顯示的配對連結。")}}}
    }
    private func configure(){
        guard let device=AVCaptureDevice.default(for:.video),let input=try? AVCaptureDeviceInput(device:device),capture.canAddInput(input) else{onError?("無法使用相機，請改貼上配對連結。");return}
        capture.addInput(input);let output=AVCaptureMetadataOutput();guard capture.canAddOutput(output) else{onError?("無法啟動掃描。");return};capture.addOutput(output);output.setMetadataObjectsDelegate(self,queue:.main);output.metadataObjectTypes=[.qr]
        let preview=AVCaptureVideoPreviewLayer(session:capture);preview.videoGravity = .resizeAspectFill;view.layer.addSublayer(preview);self.preview=preview
        let label=UILabel();label.text="掃描 Mac 控制台上的配對 QR Code";label.textColor = .white;label.textAlignment = .center;label.numberOfLines=0;label.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(label);NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:20),label.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-20),label.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor,constant:-30)])
        queue.async{[capture] in capture.startRunning()}
    }
    override func viewDidLayoutSubviews(){super.viewDidLayoutSubviews();preview?.frame=view.bounds}
    func metadataOutput(_ output:AVCaptureMetadataOutput,didOutput metadataObjects:[AVMetadataObject],from connection:AVCaptureConnection){guard !finished,let code=(metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue,code.hasPrefix("linedraw://pair?") else{return};finished=true;stop();onCode?(code)}
    func stop(){queue.async{[capture] in capture.stopRunning()}}
}
