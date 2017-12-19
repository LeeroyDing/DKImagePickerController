//
//  DKImagePickerController.swift
//  DKImagePickerController
//
//  Created by ZhangAo on 14-10-2.
//  Copyright (c) 2014年 ZhangAo. All rights reserved.
//

import UIKit
import Photos
import AssetsLibrary

@objc
public protocol DKImagePickerControllerUIDelegate {
    
    init(imagePickerController: DKImagePickerController)
    
    /**
     The picker calls -prepareLayout once at its first layout as the first message to the UIDelegate instance.
     */
    func prepareLayout(_ imagePickerController: DKImagePickerController, vc: UIViewController)
    
    /**
     The layout is to provide information about the position and visual state of items in the collection view.
     */
    func layoutForImagePickerController(_ imagePickerController: DKImagePickerController) -> UICollectionViewLayout.Type
    
    /**
     Called when the user needs to show the cancel button.
     */
    func imagePickerController(_ imagePickerController: DKImagePickerController, showsCancelButtonForVC vc: UIViewController)
    
    /**
     Called when the user needs to hide the cancel button.
     */
    func imagePickerController(_ imagePickerController: DKImagePickerController, hidesCancelButtonForVC vc: UIViewController)
    
    /**
     Called after the user changes the selection.
     */
    func imagePickerController(_ imagePickerController: DKImagePickerController, didSelectAssets: [DKAsset])
    
    /**
     Called after the user changes the selection.
     */
    func imagePickerController(_ imagePickerController: DKImagePickerController, didDeselectAssets: [DKAsset])
    
    /**
     Called when the count of the selectedAssets did reach `maxSelectableCount`.
     */
    func imagePickerControllerDidReachMaxLimit(_ imagePickerController: DKImagePickerController)
    
    /**
     Accessory view below content. default is nil.
     */
    func imagePickerControllerFooterView(_ imagePickerController: DKImagePickerController) -> UIView?
    
    /**
     Set the color of the background of the collection view.
     */
    func imagePickerControllerCollectionViewBackgroundColor() -> UIColor
 
    func imagePickerControllerCollectionImageCell() -> DKAssetGroupDetailBaseCell.Type
    
    func imagePickerControllerCollectionCameraCell() -> DKAssetGroupDetailBaseCell.Type
    
    func imagePickerControllerCollectionVideoCell() -> DKAssetGroupDetailBaseCell.Type
}

/**
 - AllPhotos: Get all photos assets in the assets group.
 - AllVideos: Get all video assets in the assets group.
 - AllAssets: Get all assets in the group.
 */
@objc
public enum DKImagePickerControllerAssetType : Int {
    case allPhotos, allVideos, allAssets
}

@objc
public enum DKImagePickerControllerSourceType : Int {
    case camera, photo, both
}

@objc
public enum DKImagePickerControllerStatus: Int {
    case unknown, selecting, exporting, completed, cancelled
}

@objc
open class DKImagePickerController : UINavigationController {
    
    @objc lazy public var UIDelegate: DKImagePickerControllerUIDelegate = {
        return DKImagePickerControllerDefaultUIDelegate(imagePickerController: self)
    }()
    
    /// Forces deselect of previous selected image. (allowSwipeToSelect will be ignored)
    @objc public var singleSelect = false
    
    /// Auto close picker on single select
    @objc public var autoCloseOnSingleSelect = true
    
    /// The maximum count of assets which the user will be able to select, a value of 0 means no limit.
    @objc public var maxSelectableCount = 0
    
    /// Set the defaultAssetGroup to specify which album is the default asset group.
    public var defaultAssetGroup: PHAssetCollectionSubtype?
    
    /// Allow swipe to select images.
    @objc public var allowSwipeToSelect: Bool = false
    
    @objc public var inline: Bool = false
    
    /// The type of picker interface to be displayed by the controller.
    @objc public var assetType: DKImagePickerControllerAssetType = .allAssets
    
    /// If sourceType is Camera will cause the assetType & maxSelectableCount & allowMultipleTypes & defaultSelectedAssets to be ignored.
    @objc public var sourceType: DKImagePickerControllerSourceType = .both {
        didSet { /// If source type changed in the scenario of sharing instance, view controller should be reinitialized.
            if (oldValue != sourceType) {
                self.hasInitialized = false
            }
        }
    }
    
    /// Whether allows to select photos and videos at the same time.
    @objc public var allowMultipleTypes = true
    
    /// Determines whether or not the rotation is enabled.
    @objc public var allowsLandscape = false
    
    /// Set the showsEmptyAlbums to specify whether or not the empty albums is shown in the picker.
    @objc public var showsEmptyAlbums = true
    
    @objc public var showsCancelButton = false {
        didSet {
            if let rootVC = self.viewControllers.first {
                self.updateCancelButtonForVC(rootVC)
            }
        }
    }
    
    /// The callback block is executed when user pressed the select button.
    @objc public var didSelectAssets: ((_ assets: [DKAsset]) -> Void)?
    
    @objc public private(set) var status = DKImagePickerControllerStatus.unknown {
        didSet {
            self.statusChanged?(self.status)
        }
    }
    
    @objc public var statusChanged: ((DKImagePickerControllerStatus) -> Void)?
    
    @objc public var selectedChanged: (() -> Void)?
    
    @objc public var exporter: DKImageAssetExporter? = DKImageAssetExporter.sharedInstance
    
    @objc public private(set) lazy var groupDataManager: DKImageGroupDataManager = {
        let configuration = DKImageGroupDataManagerConfiguration()
        configuration.assetFetchOptions = self.createDefaultAssetFetchOptions()
        
        return DKImageGroupDataManager(configuration: configuration)
    }()
    
    public private(set) var selectedAssetIdentifiers = [String]() // DKAsset.localIdentifier
    private var assets = [String : DKAsset]() // DKAsset.localIdentifier : DKAsset
    
    private lazy var extensionController: DKImageExtensionController! = {
        return DKImageExtensionController(imagePickerController: self)
    }()
    
    public convenience init() {
        let rootVC = UIViewController()
        
        self.init(rootViewController: rootVC)
    }
    
    public convenience init(groupDataManager: DKImageGroupDataManager) {
        let rootVC = UIViewController()
        self.init(rootViewController: rootVC)
        
        self.groupDataManager = groupDataManager
    }
    
    private override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)
        
        self.preferredContentSize = CGSize(width: 680, height: 600)
        
        rootViewController.navigationItem.hidesBackButton = true
    }
    
    private override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        
        self.groupDataManager.invalidate()
    }
    
    private var hasInitialized = false
    private var needShowInlineCamera = true
    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if !self.hasInitialized {
            self.hasInitialized = true
            
            if self.inline || self.sourceType == .camera {
                self.isNavigationBarHidden = true
            } else {
                self.isNavigationBarHidden = false
            }
            
            if self.sourceType != .camera {
                let rootVC = self.makeRootVC()
                rootVC.imagePickerController = self
                
                self.UIDelegate.prepareLayout(self, vc: rootVC)
                self.updateCancelButtonForVC(rootVC)
                self.setViewControllers([rootVC], animated: false)
            }
        }
        
        if self.needShowInlineCamera && self.sourceType == .camera {
            self.needShowInlineCamera = false
            self.showCamera(isInline: true)
        }
    }
    
    @objc open func makeRootVC() -> DKAssetGroupDetailVC {
      return DKAssetGroupDetailVC()
    }
    
    private func updateCancelButtonForVC(_ vc: UIViewController) {
        if self.showsCancelButton {
            self.UIDelegate.imagePickerController(self, showsCancelButtonForVC: vc)
        } else {
            self.UIDelegate.imagePickerController(self, hidesCancelButtonForVC: vc)
        }
    }
    
    private func createDefaultAssetFetchOptions() -> PHFetchOptions {
        let createImagePredicate = { () -> NSPredicate in
            let imagePredicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            
            return imagePredicate
        }
        
        let createVideoPredicate = { () -> NSPredicate in
            let videoPredicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
            
            return videoPredicate
        }
        
        var predicate: NSPredicate?
        switch self.assetType {
        case .allAssets:
            predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [createImagePredicate(), createVideoPredicate()])
        case .allPhotos:
            predicate = createImagePredicate()
        case .allVideos:
            predicate = createVideoPredicate()
        }
        
        let assetFetchOptions = PHFetchOptions()
        assetFetchOptions.predicate = predicate
        
        return assetFetchOptions
    }
    
    private var metadataFromCamera: [AnyHashable : Any]?
    private func showCamera(isInline: Bool) {
        let didCancel = { [unowned self] () in
            if self.sourceType == .camera {
                self.dismissCamera(isInline: true)
                self.dismiss()
            } else {
                self.dismissCamera()
            }
        }
        
        let didFinishCapturingImage = { [weak self] (image: UIImage, metadata: [AnyHashable : Any]?) in
            if let strongSelf = self {
                strongSelf.metadataFromCamera = metadata
                
                let didFinishEditing: ((UIImage, [AnyHashable : Any]?) -> Void) = { (image, metadata) in
                    self?.processImageFromCamera(image, metadata)
                }
                
                if strongSelf.extensionController.isExtensionTypeAvailable(.photoEditor) {
                    var extraInfo: [AnyHashable : Any] = [
                        "image" : image,
                        "didFinishEditing" : didFinishEditing,
                        ]
                    
                    if let metadata = metadata {
                        extraInfo["metadata"] = metadata
                    }
                    
                    strongSelf.extensionController.perform(extensionType: .photoEditor, with: extraInfo)
                } else {
                    didFinishEditing(image, metadata)
                }
            }
        }
        
        let didFinishCapturingVideo = { [unowned self] (videoURL: URL) in
            var newVideoIdentifier: String!
            PHPhotoLibrary.shared().performChanges({
                let assetRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
                newVideoIdentifier = assetRequest?.placeholderForCreatedAsset?.localIdentifier
            }) { (success, error) in
                DispatchQueue.main.async(execute: {
                    if success {
                        if let newAsset = PHAsset.fetchAssets(withLocalIdentifiers: [newVideoIdentifier], options: nil).firstObject {
                            if self.sourceType != .camera || self.viewControllers.count == 0 {
                                self.dismissCamera()
                            }
                            self.select(asset: DKAsset(originalAsset: newAsset))
                        }
                    } else {
                        self.dismissCamera()
                    }
                })
            }
        }
        
        self.extensionController.perform(extensionType: isInline ? .inlineCamera : .camera, with: [
            "didFinishCapturingImage" : didFinishCapturingImage,
            "didFinishCapturingVideo" : didFinishCapturingVideo,
            "didCancel" : didCancel
            ])
    }
    
    @objc open func presentCamera() {
        self.showCamera(isInline: false)
    }
    
    @objc open override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool = true, completion: (() -> Swift.Void)? = nil) {
        if self.inline {
            UIApplication.shared.keyWindow!.rootViewController!.present(viewControllerToPresent,
                                                                        animated: flag,
                                                                        completion: completion)
        } else {
            super.present(viewControllerToPresent, animated: flag, completion: completion)
        }
    }
    
    @objc open override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        if self.inline {
            UIApplication.shared.keyWindow!.rootViewController!.dismiss(animated: true, completion: nil)
        } else {
            super.dismiss(animated: true, completion: nil)
        }
    }
    
    @objc open func dismissCamera(isInline: Bool = false) {
        self.extensionController.finish(extensionType: isInline ? .inlineCamera : .camera)
    }
    
    @objc open func dismiss() {
        self.presentingViewController?.dismiss(animated: true, completion: {
            self.status = .cancelled
            
            if self.sourceType == .camera {
                self.needShowInlineCamera = true
            }
        })
    }
    
    @objc open func done() {
        let completeBlock = {
            self.status = .completed
            self.didSelectAssets?(self.selectedAssets)
            
            if self.sourceType == .camera {
                self.needShowInlineCamera = true
            }
        }
        
        self.presentingViewController?.dismiss(animated: true, completion: {
            if let exporter = self.exporter {
                self.status = .exporting
                
                exporter.exportAssetsAsynchronously(assets: self.selectedAssets, completion: { result in
                    completeBlock()
                })
            } else {
                completeBlock()
            }
        })
    }
    
    @objc open func triggerSelectedChanged() {
        if let selectedChanged = self.selectedChanged {
            selectedChanged()
        }
    }
    
    // MARK: - Capturing Image
    
    internal func processImageFromCamera(_ image: UIImage, _ metadata: [AnyHashable : Any]?) {
        self.saveImage(image, metadata) { asset in
            if self.sourceType != .camera {
                self.dismissCamera()
            }
            self.select(asset: asset)
        }
    }
    
    // MARK: - Save Image
    
    @objc open func saveImage(_ image: UIImage, _ metadata: [AnyHashable : Any]?, _ completeBlock: @escaping ((_ asset: DKAsset) -> Void)) {
        if let metadata = metadata {
            let imageData = UIImageJPEGRepresentation(image, 1)!
            
            if #available(iOS 9.0, *) {
                if let imageDataWithMetadata = self.writeMetadata(metadata, into: imageData) {
                    self.saveImageDataToAlbumForiOS9(imageDataWithMetadata, completeBlock)
                } else {
                    self.saveImageDataToAlbumForiOS9(imageData, completeBlock)
                }
            } else {
                self.saveImageDataToAlbumForiOS8(imageData, metadata, completeBlock)
            }
        } else {
            self.saveImageToAlbum(image, completeBlock)
        }
    }
    
    @objc open func saveImageToAlbum(_ image: UIImage, _ completeBlock: @escaping ((_ asset: DKAsset) -> Void)) {
        var newImageIdentifier: String!
        
        PHPhotoLibrary.shared().performChanges({
            let assetRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
            newImageIdentifier = assetRequest.placeholderForCreatedAsset!.localIdentifier
        }) { (success, error) in
            DispatchQueue.main.async(execute: {
                if success, let newAsset = PHAsset.fetchAssets(withLocalIdentifiers: [newImageIdentifier], options: nil).firstObject {
                    completeBlock(DKAsset(originalAsset: newAsset))
                } else {
                    completeBlock(DKAsset(image: image))
                }
            })
        }
    }
    
    @objc open func saveImageDataToAlbumForiOS8(_ imageData: Data, _ metadata: Dictionary<AnyHashable, Any>?, _ completeBlock: @escaping ((_ asset: DKAsset) -> Void)) {
        let library = ALAssetsLibrary()
        library.writeImageData(toSavedPhotosAlbum: imageData, metadata: metadata, completionBlock: { (newURL, error) in
            if let _ = error {
                completeBlock(DKAsset(image: UIImage(data: imageData)!))
            } else {
                if let newAsset = PHAsset.fetchAssets(withALAssetURLs: [newURL!], options: nil).firstObject {
                    completeBlock(DKAsset(originalAsset: newAsset))
                }
            }
        })
    }
    
    @objc open func saveImageDataToAlbumForiOS9(_ imageDataWithMetadata: Data, _ completeBlock: @escaping ((_ asset: DKAsset) -> Void)) {
        var newImageIdentifier: String!
        
        PHPhotoLibrary.shared().performChanges({
            if #available(iOS 9.0, *) {
                let assetRequest = PHAssetCreationRequest.forAsset()
                assetRequest.addResource(with: .photo, data: imageDataWithMetadata, options: nil)
                newImageIdentifier = assetRequest.placeholderForCreatedAsset!.localIdentifier
            } else {
                // Fallback on earlier versions
            }
        }) { (success, error) in
            DispatchQueue.main.async(execute: {
                if success, let newAsset = PHAsset.fetchAssets(withLocalIdentifiers: [newImageIdentifier], options: nil).firstObject {
                    completeBlock(DKAsset(originalAsset: newAsset))
                } else {
                    completeBlock(DKAsset(image: UIImage(data: imageDataWithMetadata)!))
                }
            })
            
        }
    }
    
    @objc open func writeMetadata(_ metadata: Dictionary<AnyHashable, Any>, into imageData: Data) -> Data? {
        let source = CGImageSourceCreateWithData(imageData as CFData, nil)!
        let UTI = CGImageSourceGetType(source)!
        
        let newImageData = NSMutableData()
        if let destination = CGImageDestinationCreateWithData(newImageData, UTI, 1, nil) {
            CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary)
            if CGImageDestinationFinalize(destination) {
                return newImageData as Data
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
    
    // MARK: - Selection
        
    @objc open func select(asset: DKAsset, updateGroupDetailVC: Bool = true) {
        if self.singleSelect {
            self.deselectAll()
        }
        
        if self.assets[asset.localIdentifier] != nil { return }
        
        self.selectedAssetIdentifiers.append(asset.localIdentifier)
        self.assets[asset.localIdentifier] = asset
        self.clearSelectedAssetsCache()
        
        if self.sourceType == .camera || (self.singleSelect && self.autoCloseOnSingleSelect) {
            self.done()
        } else {
            self.triggerSelectedChanged()
            self.UIDelegate.imagePickerController(self, didSelectAssets: [asset])
            
            if updateGroupDetailVC, let rootVC = self.viewControllers.first as? DKAssetGroupDetailVC {
                rootVC.collectionView?.reloadData()
            }
        }
    }
    
    @objc open func select(assets: [DKAsset], updateGroupDetailVC: Bool = true) {
        var needsUpdateGroupDetailVC = false
        
        for asset in assets {
            self.select(asset: asset, updateGroupDetailVC: false)
            needsUpdateGroupDetailVC = true
        }
        
        if needsUpdateGroupDetailVC, updateGroupDetailVC, let rootVC = self.viewControllers.first as? DKAssetGroupDetailVC {
            rootVC.collectionView?.reloadData()
        }
    }
    
    @objc open func deselect(asset: DKAsset, updateGroupDetailVC: Bool = true) {
        if self.assets[asset.localIdentifier] == nil { return }
        
        self.selectedAssetIdentifiers.remove(at: self.selectedAssetIdentifiers.index(of: asset.localIdentifier)!)
        self.assets[asset.localIdentifier] = nil
        self.clearSelectedAssetsCache()
        
        self.triggerSelectedChanged()
        self.UIDelegate.imagePickerController(self, didDeselectAssets: [asset])
        
        if updateGroupDetailVC, let rootVC = self.viewControllers.first as? DKAssetGroupDetailVC {
            rootVC.collectionView?.reloadData()
        }
    }
    
    @objc open func deselectAll(updateGroupDetailVC: Bool = true) {
        if self.selectedAssetIdentifiers.count > 0 {
            let assets = self.selectedAssets
            self.selectedAssetIdentifiers.removeAll()
            self.assets.removeAll()
            self.clearSelectedAssetsCache()
            
            self.triggerSelectedChanged()
            self.UIDelegate.imagePickerController(self, didDeselectAssets: assets)
            
            
            if updateGroupDetailVC, let rootVC = self.viewControllers.first as? DKAssetGroupDetailVC {
                rootVC.collectionView?.reloadData()
            }
        }
    }
    
    @objc open func setSelectedAssets(assets: [DKAsset]) {
        if assets.count > 0 {
            self.deselectAll(updateGroupDetailVC: false)
            self.select(assets: assets, updateGroupDetailVC: true)
        } else {
            self.deselectAll(updateGroupDetailVC: true)
        }
    }
    
    open func index(of asset: DKAsset) -> Int? {
        if self.contains(asset: asset) {
            return self.selectedAssetIdentifiers.index(of: asset.localIdentifier)
        } else {
            return nil
        }
    }
    
    @objc func contains(asset: DKAsset) -> Bool {
        return self.assets[asset.localIdentifier] != nil
    }
    
    private var internalSelectedAssetsCache: [DKAsset]?
    @objc public var selectedAssets: [DKAsset] {
        get {
            if self.internalSelectedAssetsCache != nil {
                return self.internalSelectedAssetsCache!
            }
            
            var assets = [DKAsset]()
            for assetIdentifier in self.selectedAssetIdentifiers {
                assets.append(self.assets[assetIdentifier]!)
            }
            
            self.internalSelectedAssetsCache = assets

            return assets
        }
    }
    
    private func clearSelectedAssetsCache() {
        self.internalSelectedAssetsCache = nil
    }
    
    // MARK: - Orientation
    
    @objc open override var shouldAutorotate : Bool {
        return self.allowsLandscape && self.sourceType != .camera ? true : false
    }
    
    @objc open override var supportedInterfaceOrientations : UIInterfaceOrientationMask {
        if self.allowsLandscape {
            return super.supportedInterfaceOrientations
        } else {
            return UIInterfaceOrientationMask.portrait
        }
    }
    
    // MARK: - Gallery
    
    public func showGallery(with presentationIndex: Int?,
                            presentingFromImageView: UIImageView?,
                            groupId: String) {
        var extraInfo: [AnyHashable : Any] = [
            "groupId" : groupId
        ]
        
        if let presentationIndex = presentationIndex {
            extraInfo["presentationIndex"] = presentationIndex
        }
        
        if let presentingFromImageView = presentingFromImageView {
            extraInfo["presentingFromImageView"] = presentingFromImageView
        }
        
        self.extensionController.perform(extensionType: .gallery, with: extraInfo)
    }
    
}
