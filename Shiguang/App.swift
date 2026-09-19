import UIKit
import Photos
import PhotosUI

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = PhotoController()
        window.tintColor = UIColor(red: 137/255, green: 207/255, blue: 240/255, alpha: 1)
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

struct ReviewState: Codable {
    var order: [String] = []
    var pending: Set<String> = []
    var visited: Set<String> = []
    var batchStart: Int? = nil
    var position: Int { order.isEmpty ? 0 : min(25,max(1,index-(batchStart ?? max(0,index-visited.count))+1)) }
    var index = 0
    var current: String? { order.indices.contains(index) ? order[index] : nil }
    mutating func reconcile(_ available: [String]) {
        let anchor = current, allowed = Set(available)
        order = order.filter { allowed.contains($0) }
        pending.formIntersection(allowed); visited.formIntersection(allowed)
        let known = Set(order)
        order += available.filter { !known.contains($0) }.shuffled()
        index = anchor.flatMap { order.firstIndex(of: $0) } ?? min(index, max(0, order.count - 1))
    }
}

final class PhotoCell: UICollectionViewCell {
    let image = UIImageView()
    let mark = UILabel()
    var representedID: String?
    var request: PHImageRequestID = PHInvalidImageRequestID
    override init(frame: CGRect) {
        super.init(frame: frame)
        image.contentMode = .scaleAspectFill; image.clipsToBounds = true
        image.backgroundColor = UIColor(white: 0.12, alpha: 1)
        contentView.addSubview(image)
        mark.text = "↑ 待删除"; mark.textAlignment = .center
        mark.textColor = .white; mark.backgroundColor = UIColor.systemPink.withAlphaComponent(0.45)
        contentView.addSubview(mark)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override func layoutSubviews() { super.layoutSubviews(); image.frame = contentView.bounds; mark.frame = contentView.bounds }
    override func prepareForReuse() {
        super.prepareForReuse()
        PHImageManager.default().cancelImageRequest(request)
        representedID = nil; image.image = nil; contentView.transform = .identity; contentView.alpha = 1
    }
}

final class PhotoController: UIViewController, UIScrollViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate, PHPhotoLibraryChangeObserver {
    private let blue = UIColor(red: 137/255, green: 207/255, blue: 240/255, alpha: 1)
    private var state = ReviewState()
    private var assets: [String: PHAsset] = [:]
    private var dayIDs: [String] = []
    private var dayAnchor: String?
    private var rows = 2
    private var chrome = false
    private var locked = false
    private var requestingAccess = false
    private var accessAttempt = UUID()
    private var accessFeedback: String?
    private let accessButton = UIButton(type: .system)
    private var observingLibrary = false
    private var querying = false
    private var reloadNeeded = false
    private var lastMarked: String?
    private var request: PHImageRequestID = PHInvalidImageRequestID
    private var imageToken = UUID()
    private let zoom = UIScrollView()
    private let photo = UIImageView()
    private let titleLabel = UILabel(), progress = UILabel(), message = UILabel()
    private let menu = UIButton(type: .system), undo = UIButton(type: .system), trash = UIButton(type: .system)
    private let countLabel = UILabel()
    private let flow = UICollectionViewFlowLayout()
    private lazy var grid = UICollectionView(frame: .zero, collectionViewLayout: flow)
    private var draggedCell: PhotoCell?
    private var draggedID: String?
    private lazy var singlePan = UIPanGestureRecognizer(target: self, action: #selector(panPhoto(_:)))
    private lazy var gridPan = UIPanGestureRecognizer(target: self, action: #selector(panTile(_:)))
    private lazy var dayPinch = UIPinchGestureRecognizer(target: self, action: #selector(pinchDay(_:)))
    private var lastSize = CGSize.zero
    private let live = PHLivePhotoView()
    private var liveRequest: PHImageRequestID = PHInvalidImageRequestID
    private var pinchFromOriginal = true
    private var dayPinchID: String?
    private var autoLive: Bool { UserDefaults.standard.bool(forKey: "autoLive") }

    override var prefersStatusBarHidden: Bool { true }
    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 0.04, green: 0.06, blue: 0.08, alpha: 1)
        if let data = UserDefaults.standard.data(forKey: "review"), let saved = try? JSONDecoder().decode(ReviewState.self, from: data) { state = saved }
        if state.batchStart == nil { state.batchStart = max(0,state.index-state.visited.count) }
        zoom.delegate = self; zoom.minimumZoomScale = 0.65; zoom.maximumZoomScale = 8
        zoom.showsHorizontalScrollIndicator = false; zoom.showsVerticalScrollIndicator = false
        zoom.contentInsetAdjustmentBehavior = .never
        live.contentMode = .scaleAspectFit; live.isUserInteractionEnabled = false; photo.addSubview(live)
        photo.contentMode = .scaleAspectFit; zoom.addSubview(photo); view.addSubview(zoom)
        singlePan.delegate = self; singlePan.maximumNumberOfTouches = 1; zoom.addGestureRecognizer(singlePan)
        zoom.panGestureRecognizer.require(toFail: singlePan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleChrome))
        tap.require(toFail: singlePan); zoom.addGestureRecognizer(tap)
        flow.scrollDirection = .horizontal; flow.minimumLineSpacing = 6; flow.minimumInteritemSpacing = 6
        grid.backgroundColor = view.backgroundColor; grid.dataSource = self; grid.delegate = self
        grid.register(PhotoCell.self, forCellWithReuseIdentifier: "photo")
        grid.decelerationRate = .normal; grid.alwaysBounceHorizontal = true
        grid.showsHorizontalScrollIndicator = false; grid.contentInsetAdjustmentBehavior = .never
        grid.isHidden = true; view.addSubview(grid)
        gridPan.delegate = self; gridPan.maximumNumberOfTouches = 1; grid.addGestureRecognizer(gridPan)
        grid.panGestureRecognizer.require(toFail: gridPan)
        grid.addGestureRecognizer(dayPinch)
        for label in [titleLabel, progress, message, countLabel] { label.textColor = blue }
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        progress.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        message.font = .systemFont(ofSize: 15); message.numberOfLines = 0; message.textAlignment = .center
        message.isUserInteractionEnabled = false
        accessButton.setTitle("允许访问照片", for: .normal)
        accessButton.backgroundColor = blue
        accessButton.setTitleColor(.black, for: .normal)
        accessButton.layer.cornerRadius = 14
        accessButton.addAction(UIAction { [weak self] _ in self?.requestAccess() }, for: .touchUpInside)
        configure(menu, symbol: "ellipsis", action: #selector(showMenu))
        configure(undo, symbol: "arrow.uturn.backward", action: #selector(undoMark))
        configure(trash, symbol: "trash", action: #selector(review))
        trash.backgroundColor = blue; trash.tintColor = UIColor(red: 0.05, green: 0.12, blue: 0.16, alpha: 1)
        trash.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 31, weight: .regular), forImageIn: .normal)
        countLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        countLabel.textColor = trash.tintColor; countLabel.textAlignment = .center
        countLabel.backgroundColor = blue; countLabel.isUserInteractionEnabled = false; trash.addSubview(countLabel)
        for v in [titleLabel, progress, menu, undo, trash, message] { view.addSubview(v) }
        view.addSubview(accessButton)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: UIApplication.didBecomeActiveNotification, object: nil)
        updateChrome()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refresh()
    }
    deinit {
        if observingLibrary { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
        NotificationCenter.default.removeObserver(self)
    }
    private func configure(_ button: UIButton, symbol: String, action: Selector) {
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 24, weight: .medium), forImageIn: .normal)
        button.tintColor = blue; button.backgroundColor = UIColor(white: 0.1, alpha: 0.9)
        button.layer.cornerRadius = 29; button.addTarget(self, action: action, for: .touchUpInside)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds, safe = view.safeAreaInsets
        if lastSize != b.size {
            lastSize = b.size; zoom.setZoomScale(1, animated: false); zoom.frame = b; photo.frame = zoom.bounds; zoom.contentSize = b.size
        }
        live.frame = photo.bounds
        let y = safe.top + 10
        titleLabel.frame = CGRect(x: safe.left + 22, y: y, width: max(100, b.width - safe.left - safe.right - 205), height: 50)
        progress.frame = CGRect(x: b.width - safe.right - 147, y: y, width: 75, height: 50)
        menu.frame = CGRect(x: b.width - safe.right - 68, y: y, width: 50, height: 50); menu.layer.cornerRadius = 25
        undo.frame = CGRect(x: safe.left + 22, y: b.height - safe.bottom - 76, width: 58, height: 58)
        trash.frame = CGRect(x: b.width - safe.right - 80, y: undo.frame.minY, width: 58, height: 58)
        countLabel.frame = CGRect(x: 22, y: 27, width: 14, height: 13)
        message.frame = CGRect(x: 28, y: b.midY - 100, width: b.width - 56, height: 140)
        accessButton.frame = CGRect(x: max(28, b.midX - 120), y: b.midY + 48, width: min(240, b.width - 56), height: 52)
        let newFrame = CGRect(x: safe.left, y: safe.top + 74, width: b.width - safe.left - safe.right, height: max(100, b.height - safe.top - safe.bottom - 166))
        if grid.frame != newFrame { grid.frame = newFrame; flow.invalidateLayout() }
    }
    private func save() { if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: "review") } }
    private func updateChrome() {
        titleLabel.text = dayAnchor == nil ? "拾光" : dayAnchor.flatMap { assets[$0]?.creationDate }.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) }
        progress.text = "\(state.position) / 25"; countLabel.text = state.pending.count > 99 ? "99+" : "\(state.pending.count)"
        for v in [titleLabel, progress, menu, undo, trash] { v.isHidden = !chrome }
        undo.isEnabled = !state.pending.isEmpty && !locked; undo.alpha = undo.isEnabled ? 1 : 0.4
        trash.isEnabled = !locked; menu.isEnabled = !locked
        undo.accessibilityLabel = "撤销最近的删除标记"; trash.accessibilityLabel = "待删除 \(state.pending.count) 张，集中确认"
        menu.accessibilityLabel = "更多选项"
    }
    @objc private func toggleChrome() { chrome.toggle(); updateChrome() }
    private func showAccessFeedback(_ text: String) {
        accessFeedback = text
        message.text = text
        chrome = true
        updateChrome()
    }
    @objc private func requestAccess() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if requestingAccess {
            showAccessFeedback("正在等待系统授权响应…\n若未弹窗，请等待 10 秒后重试")
            return
        }
        switch status {
        case .notDetermined:
            guard view.window != nil else {
                showAccessFeedback("界面尚未就绪，请稍后重试")
                return
            }
            guard UIApplication.shared.applicationState == .active else {
                showAccessFeedback("请回到拾光前台后再次点击")
                return
            }
            // Menu dismissal must finish before asking the system to present its prompt.
            if let presented = presentedViewController {
                presented.dismiss(animated: true) { [weak self] in self?.requestAccess() }
                return
            }
            requestingAccess = true
            let attempt = UUID()
            accessAttempt = attempt
            showAccessFeedback("正在请求照片访问权限…")
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
                DispatchQueue.main.async {
                    guard let self = self, self.accessAttempt == attempt else { return }
                    self.requestingAccess = false
                    self.accessFeedback = status == .notDetermined ? "系统未完成授权，请重试" : nil
                    self.refresh()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self = self, self.accessAttempt == attempt, self.requestingAccess else { return }
                self.requestingAccess = false
                self.showAccessFeedback("系统尚未返回授权结果\n请截图此页反馈，或点击按钮重试\n权限状态：\(PHPhotoLibrary.authorizationStatus(for: .readWrite).rawValue) · P3")
            }
        case .authorized, .limited:
            accessFeedback = nil
            refresh()
        case .denied:
            showAccessFeedback("照片访问已被拒绝，正在打开设置\n权限状态：2 · P3")
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        case .restricted:
            showAccessFeedback("相册访问受到系统限制\n请检查屏幕使用时间或设备管理限制\n权限状态：1 · P3")
        @unknown default:
            showAccessFeedback("未知权限状态：\(status.rawValue) · P3")
        }
    }
    @objc private func refresh() {
        if locked || querying { reloadNeeded = true; return }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        accessButton.isHidden = status == .authorized || status == .limited
        accessButton.setTitle(status == .denied ? "打开照片权限设置" : "允许访问照片", for: .normal)
        guard status == .authorized || status == .limited else { assets = [:]; dayAnchor = nil; dayIDs = []; grid.isHidden = true; imageToken = UUID(); PHImageManager.default().cancelImageRequest(request); photo.image = nil; message.text = accessFeedback ?? (status == .restricted ? "相册访问受到系统限制\n权限状态：1 · P3" : (status == .denied ? "需要在设置中允许照片访问\n权限状态：2 · P3" : "需要相册访问权限\n请点击下方按钮 · P3")); chrome = true; updateChrome(); return }
        if !observingLibrary {
            PHPhotoLibrary.shared().register(self)
            observingLibrary = true
        }
        querying = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = PHAsset.fetchAssets(with: .image, options: nil)
            var found: [String: PHAsset] = [:], ids: [String] = []
            result.enumerateObjects { asset, _, _ in found[asset.localIdentifier] = asset; ids.append(asset.localIdentifier) }
            DispatchQueue.main.async {
                self.querying = false; self.assets = found; self.state.reconcile(ids); self.save()
                if self.dayAnchor != nil {
                    self.dayIDs = self.dayIDs.filter { found[$0] != nil }
                    if self.dayIDs.isEmpty { self.leaveDay() } else { self.grid.reloadData(); self.updateChrome() }
                } else { self.showPhoto() }
                if self.reloadNeeded { self.reloadNeeded = false; self.refresh() }
            }
        }
    }
    func photoLibraryDidChange(_ changeInstance: PHChange) { DispatchQueue.main.async { self.refresh() } }
    private func showPhoto() {
        live.stopPlayback(); live.livePhoto = nil; PHImageManager.default().cancelImageRequest(liveRequest)
        updateChrome(); zoom.setZoomScale(1, animated: false); photo.transform = .identity; photo.alpha = 1
        PHImageManager.default().cancelImageRequest(request); imageToken = UUID(); let token = imageToken
        photo.image = nil
        guard let id = state.current, let asset = assets[id] else { message.text = "暂无可浏览照片\n轻点授权，或在菜单调整可访问的照片"; chrome = true; updateChrome(); return }
        message.text = ""
        if autoLive && asset.mediaSubtypes.contains(.photoLive) {
            let options = PHLivePhotoRequestOptions(); options.isNetworkAccessAllowed = true
            liveRequest = PHImageManager.default().requestLivePhoto(for: asset, targetSize: view.bounds.size, contentMode: .aspectFit, options: options) { [weak self] value, _ in
                DispatchQueue.main.async { guard let self = self, self.imageToken == token, self.dayAnchor == nil, self.autoLive else { return }; self.live.livePhoto = value; self.live.startPlayback(with: .full) }
            }
        }
        let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = true; options.deliveryMode = .opportunistic
        let screen = view.bounds.size, scale = UIScreen.main.scale
        let target = CGSize(width: min(4096, screen.width * scale * 2), height: min(4096, screen.height * scale * 2))
        request = PHImageManager.default().requestImage(for: asset, targetSize: target, contentMode: .aspectFit, options: options) { image, info in
            DispatchQueue.main.async {
                guard self.imageToken == token else { return }
                if let image = image { self.photo.image = image; self.message.text = "" }
                else if info?[PHImageErrorKey] != nil { self.message.text = "暂时无法载入，可滑动切换" }
            }
        }
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { scrollView === zoom ? photo : nil }
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        guard scrollView === zoom else { return }; pinchFromOriginal = zoom.zoomScale <= 1; zoom.minimumZoomScale = pinchFromOriginal ? 0.65 : 1; live.stopPlayback()
    }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        guard scrollView === zoom else { return }
        if pinchFromOriginal && scale < 0.84 { zoom.setZoomScale(1, animated: false); enterDay() }
        else if scale < 1 { zoom.setZoomScale(1, animated: true) }
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard !locked else { return false }
        if gestureRecognizer === singlePan { return zoom.zoomScale <= 1.02 && zoom.pinchGestureRecognizer?.state != .changed }
        if gestureRecognizer === gridPan { let v = gridPan.velocity(in: grid); return v.y < 0 && abs(v.y) > abs(v.x) * 1.25 }
        return true
    }
    @objc private func panPhoto(_ pan: UIPanGestureRecognizer) {
        guard state.current != nil else { return }
        let t = pan.translation(in: view), velocity = pan.velocity(in: view), vertical = abs(t.y) > abs(t.x)
        if pan.state == .changed {
            photo.transform = CGAffineTransform(translationX: vertical ? t.x * 0.1 : t.x, y: vertical ? min(0,t.y) : 0)
            photo.alpha = vertical ? max(0.3,1 + t.y/view.bounds.height) : 1
        } else if pan.state == .ended {
            let discard = vertical && t.y < -60
            let next = !vertical && (abs(t.x) > 65 || (abs(t.x) > 20 && abs(velocity.x) > 650))
            if discard || next {
                locked = true
                UIView.animate(withDuration: 0.23, animations: { self.photo.transform = CGAffineTransform(translationX: discard ? 0 : (t.x < 0 ? -self.view.bounds.width : self.view.bounds.width), y: discard ? -self.view.bounds.height : 0); self.photo.alpha = 0.1 }) { _ in
                    self.locked = false; self.advance(discard: discard, backwards: !discard && t.x > 0)
                }
            } else { resetPhoto() }
        } else if pan.state == .cancelled { resetPhoto() }
    }
    private func resetPhoto() { UIView.animate(withDuration: 0.2) { self.photo.transform = .identity; self.photo.alpha = 1 } }
    private func advance(discard: Bool, backwards: Bool) {
        guard let id = state.current else { return }
        if backwards { state.index = max(state.batchStart ?? 0,state.index - 1); save(); showPhoto(); return }
        if discard { mark(id) }
        state.visited.insert(id)
        let due = state.position >= 25 || state.index == state.order.count - 1
        if !due { state.index += 1 }
        save(); showPhoto(); if due { review() }
    }
    private func mark(_ id: String) { state.pending.insert(id); lastMarked = id; UIImpactFeedbackGenerator(style: .light).impactOccurred(); save(); updateChrome() }
    @objc private func undoMark() {
        guard !locked, let id = lastMarked ?? state.pending.sorted().last else { return }
        state.pending.remove(id); lastMarked = nil; save(); updateChrome()
        if dayAnchor != nil { grid.reloadData() } else if let i = state.order.firstIndex(of: id) { state.index = i; save(); showPhoto() }
    }
    private func enterDay() {
        guard !locked, dayAnchor == nil, let id = state.current else { return }
        guard let date = assets[id]?.creationDate else {
            let alert = UIAlertController(title: "这张照片没有拍摄日期", message: "可以继续随机浏览其他照片。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default)); present(alert, animated: true); return
        }
        dayIDs = assets.values.filter { $0.creationDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false }.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }.map(\.localIdentifier)
        live.stopPlayback(); live.livePhoto = nil
        dayAnchor = id; state.visited.insert(id); save(); rows = 2
        grid.reloadData(); flow.invalidateLayout(); grid.layoutIfNeeded()
        grid.isHidden = false; grid.alpha = 0
        if let i = dayIDs.firstIndex(of: id) { grid.scrollToItem(at: IndexPath(item: i, section: 0), at: .left, animated: false) }
        UIView.animate(withDuration: 0.22) { self.grid.alpha = 1 }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(); updateChrome()
    }
    private func leaveDay() {
        guard dayAnchor != nil else { return }
        dayAnchor = nil; dayIDs = []; grid.isHidden = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred(); showPhoto()
        if state.visited.count >= 25 { review() }
    }
    @objc private func pinchDay(_ pinch: UIPinchGestureRecognizer) {
        guard !locked else { return }
        if pinch.state == .began { dayPinchID = grid.indexPathForItem(at: pinch.location(in: grid)).map { dayIDs[$0.item] } }
        if pinch.state == .ended {
            if pinch.scale < 0.85 { rows = 3 }
            else if pinch.scale > 1.18 { if let id = dayPinchID, let asset = assets[id] { present(PhotoViewer(assets: [asset], autoLive: autoLive), animated: true) }; return }
            let anchor = grid.indexPathsForVisibleItems.sorted().first
            grid.performBatchUpdates({ self.flow.invalidateLayout() }) { _ in if let anchor = anchor { self.grid.scrollToItem(at: anchor, at: .left, animated: true) } }
        }
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { dayIDs.count }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let h = floor((collectionView.bounds.height - CGFloat(rows-1)*6) / CGFloat(rows))
        return CGSize(width: min(collectionView.bounds.width*0.78, h*0.78), height: h)
    }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "photo", for: indexPath) as! PhotoCell
        let id = dayIDs[indexPath.item]; cell.representedID = id; cell.mark.isHidden = !state.pending.contains(id)
        if let asset = assets[id] {
            let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = true
            cell.request = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 700, height: 700), contentMode: .aspectFill, options: options) { [weak cell] image, _ in
                DispatchQueue.main.async { if cell?.representedID == id { cell?.image.image = image } }
            }
        }
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) { toggleChrome() }
    @objc private func panTile(_ pan: UIPanGestureRecognizer) {
        if pan.state == .began {
            grid.setContentOffset(grid.contentOffset, animated: false)
            if let path = grid.indexPathForItem(at: pan.location(in: grid)) { draggedCell = grid.cellForItem(at: path) as? PhotoCell; draggedID = dayIDs[path.item] }
        } else if pan.state == .changed { let y = min(0,pan.translation(in: grid).y); draggedCell?.contentView.transform = CGAffineTransform(translationX: 0,y: y); draggedCell?.contentView.alpha = max(0.3,1+y/500) }
        else if pan.state == .ended || pan.state == .cancelled {
            let cell = draggedCell, id = draggedID, commit = pan.state == .ended && pan.translation(in: grid).y < -55
            draggedCell = nil; draggedID = nil
            if commit, let id = id {
                locked = true
                UIView.animate(withDuration: 0.2, animations: { cell?.contentView.transform = CGAffineTransform(translationX: 0,y: -self.grid.bounds.height); cell?.contentView.alpha = 0 }) { _ in
                    self.locked = false; self.mark(id); cell?.contentView.transform = .identity; cell?.contentView.alpha = 1; self.grid.reloadData()
                }
            } else { UIView.animate(withDuration: 0.2) { cell?.contentView.transform = .identity; cell?.contentView.alpha = 1 } }
        }
    }
    @objc private func review() {
        guard !locked, presentedViewController == nil else { return }
        chrome = true; updateChrome()
        if state.pending.isEmpty {
            let alert = UIAlertController(title: "本轮已浏览 \(state.visited.count) 张", message: "没有待删除照片。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "继续浏览", style: .default) { _ in self.finishBatch([]) })
            alert.addAction(UIAlertAction(title: "返回", style: .cancel)); present(alert, animated: true); return
        }
        let alert = UIAlertController(title: "本轮第 \(state.position) / 25 张", message: "已标记 \(state.pending.count) 张照片", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "回看已标记", style: .default) { _ in
            let items = self.state.pending.sorted().compactMap { self.assets[$0] }
            let viewer = PhotoViewer(assets: items, autoLive: self.autoLive)
            viewer.isMarked = { self.state.pending.contains($0) }
            viewer.toggleMark = { id in if self.state.pending.contains(id) { self.state.pending.remove(id) } else { self.state.pending.insert(id) }; self.save(); self.updateChrome(); self.grid.reloadData() }
            self.present(viewer, animated: true)
        })
        alert.addAction(UIAlertAction(title: "删除已标记照片", style: .destructive) { _ in self.deletePending() })
        alert.addAction(UIAlertAction(title: "继续检查", style: .cancel)); present(alert, animated: true)
    }
    private func deletePending() {
        guard !state.pending.isEmpty else { return }
        let ids = state.pending, fetched = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
        locked = true; updateChrome()
        PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.deleteAssets(fetched) }) { success, error in
            DispatchQueue.main.async {
                self.locked = false
                if success { self.finishBatch(ids) }
                else {
                    let alert = UIAlertController(title: "照片未删除", message: "操作取消或未完成，待删除标记已保留。", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "好", style: .default)); self.present(alert, animated: true); self.updateChrome()
                }
                self.refresh()
            }
        }
    }
    private func finishBatch(_ removed: Set<String>) {
        let old = state.current
        state.order.removeAll { removed.contains($0) }; state.pending.removeAll(); state.visited.removeAll(); lastMarked = nil
        if let old = old, let i = state.order.firstIndex(of: old) { state.index = min(i+1, max(0,state.order.count-1)) }
        else { state.index = min(state.index,max(0,state.order.count-1)) }
        state.batchStart = state.index
        save(); if dayAnchor == nil { showPhoto() } else { dayIDs.removeAll { removed.contains($0) }; grid.reloadData(); updateChrome() }
    }
    @objc private func showMenu() {
        let alert = UIAlertController(title: "拾光 · iOS 1.7.0 · P3", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: dayAnchor == nil ? "回到那天" : "回到单张", style: .default) { _ in if self.dayAnchor == nil { self.enterDay() } else { self.leaveDay() } })
        if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited { alert.addAction(UIAlertAction(title: "调整可访问照片", style: .default) { _ in PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: self) }) }
        alert.addAction(UIAlertAction(title: "动态照片：" + (autoLive ? "自动播放" : "不播放"), style: .default) { _ in
            let settings = UIAlertController(title: "动态照片", message: nil, preferredStyle: .alert)
            for (title, enabled) in [("自动播放",true),("不播放",false)] { settings.addAction(UIAlertAction(title: title, style: .default) { _ in UserDefaults.standard.set(enabled,forKey: "autoLive"); if self.dayAnchor == nil { self.showPhoto() } }) }
            settings.addAction(UIAlertAction(title: "取消", style: .cancel)); self.present(settings,animated:true)
        })
        alert.addAction(UIAlertAction(title: "相册访问权限", style: .default) { _ in self.requestAccess() })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel)); alert.popoverPresentationController?.sourceView = menu; alert.popoverPresentationController?.sourceRect = menu.bounds
        present(alert, animated: true)
    }
}

final class PhotoViewer: UIViewController, UIScrollViewDelegate {
    private let items: [PHAsset]
    private let autoLive: Bool
    var isMarked: ((String) -> Bool)?
    var toggleMark: ((String) -> Void)?
    private var index = 0
    private let scroll = UIScrollView(), image = UIImageView(), live = PHLivePhotoView()
    private let caption = UILabel(), markButton = UIButton(type: .system)
    private var token = UUID()
    private var requests: [PHImageRequestID] = []
    init(assets: [PHAsset], autoLive: Bool) { self.items = assets; self.autoLive = autoLive; super.init(nibName:nil,bundle:nil); modalPresentationStyle = .fullScreen }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black; view.tintColor = UIColor(red:137/255,green:207/255,blue:240/255,alpha:1)
        scroll.delegate = self; scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 8; scroll.contentInsetAdjustmentBehavior = .never
        image.contentMode = .scaleAspectFit; live.contentMode = .scaleAspectFit; live.isUserInteractionEnabled = false
        image.addSubview(live); scroll.addSubview(image); view.addSubview(scroll)
        let bar = UIStackView(); bar.axis = .vertical; bar.spacing = 8; bar.alignment = .fill; bar.translatesAutoresizingMaskIntoConstraints = false
        caption.textAlignment = .center; caption.textColor = view.tintColor; bar.addArrangedSubview(caption)
        let controls = UIStackView(); controls.distribution = .fillEqually
        let previousButton = UIButton(type: .system)
        previousButton.setTitle("上一张", for: .normal)
        previousButton.addAction(UIAction { [weak self] _ in self?.showPreviousPhoto() }, for: .touchUpInside)
        controls.addArrangedSubview(previousButton)
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("返回", for: .normal)
        closeButton.addAction(UIAction { [weak self] _ in self?.closeViewer() }, for: .touchUpInside)
        controls.addArrangedSubview(closeButton)
        let nextButton = UIButton(type: .system)
        nextButton.setTitle("下一张", for: .normal)
        nextButton.addAction(UIAction { [weak self] _ in self?.showNextPhoto() }, for: .touchUpInside)
        controls.addArrangedSubview(nextButton)
        controls.heightAnchor.constraint(equalToConstant:48).isActive = true; bar.addArrangedSubview(controls)
        markButton.addAction(UIAction { [weak self] _ in self?.toggle() }, for: .touchUpInside); markButton.isHidden = toggleMark == nil; bar.addArrangedSubview(markButton)
        view.addSubview(bar)
        NSLayoutConstraint.activate([bar.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor,constant:16),bar.trailingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.trailingAnchor,constant:-16),bar.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor,constant:-12)])
        load()
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); let frame = CGRect(x:0,y:view.safeAreaInsets.top,width:view.bounds.width,height:max(1,view.bounds.height-view.safeAreaInsets.top-view.safeAreaInsets.bottom-150)); if scroll.frame != frame { scroll.setZoomScale(1,animated:false); scroll.frame=frame; image.frame=scroll.bounds; live.frame=image.bounds; scroll.contentSize=image.bounds.size } }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { image }
    private func load() {
        guard items.indices.contains(index) else { return }
        for request in requests { PHImageManager.default().cancelImageRequest(request) }; requests=[]
        token=UUID(); let currentToken=token; let asset=items[index]; live.stopPlayback(); live.livePhoto=nil; image.image=nil; scroll.setZoomScale(1,animated:false)
        caption.text="\(index+1) / \(items.count)"; updateMark()
        let options=PHImageRequestOptions(); options.isNetworkAccessAllowed=true
        requests.append(PHImageManager.default().requestImage(for:asset,targetSize:CGSize(width:4096,height:4096),contentMode:.aspectFit,options:options) { [weak self] value,_ in DispatchQueue.main.async { guard let self=self,self.token==currentToken else { return }; self.image.image=value } })
        if autoLive && asset.mediaSubtypes.contains(.photoLive) {
            let options=PHLivePhotoRequestOptions(); options.isNetworkAccessAllowed=true
            requests.append(PHImageManager.default().requestLivePhoto(for:asset,targetSize:CGSize(width:1600,height:1600),contentMode:.aspectFit,options:options) { [weak self] value,_ in DispatchQueue.main.async { guard let self=self,self.token==currentToken else { return }; self.live.livePhoto=value; self.live.startPlayback(with:.full) } })
        }
    }
    private func updateMark(){ guard items.indices.contains(index) else { return }; markButton.setTitle(isMarked?(items[index].localIdentifier) == true ? "取消删除标记，保留照片" : "已保留 · 重新标记删除",for:.normal) }
    @objc private func toggle(){ guard items.indices.contains(index) else { return }; toggleMark?(items[index].localIdentifier); updateMark() }
    @objc private func showPreviousPhoto(){ if index>0 { index-=1;load() } }
    @objc private func showNextPhoto(){ if index+1<items.count { index+=1;load() } }
    @objc private func closeViewer(){ dismiss(animated:true) }
    override func viewWillDisappear(_ animated:Bool){ super.viewWillDisappear(animated); token=UUID();live.stopPlayback();for request in requests { PHImageManager.default().cancelImageRequest(request) } }
}
