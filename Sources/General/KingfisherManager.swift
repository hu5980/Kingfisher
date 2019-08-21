//
//  KingfisherManager.swift
//  Kingfisher
//
//  Created by Wei Wang on 15/4/6.
//
//  Copyright (c) 2018 Wei Wang <onevcat@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.


import Foundation

/// The downloading progress block type.
/// The parameter value is the `receivedSize` of current response.
/// The second parameter is the total expected data length from response's "Content-Length" header.
/// If the expected length is not available, this block will not be called.
public typealias DownloadProgressBlock = ((_ receivedSize: Int64, _ totalSize: Int64) -> Void)

/// Represents the result of a Kingfisher retrieving image task.
public struct RetrieveImageResult {
    
    /// Gets the image object of this result.
    public let image: Image
    
    /// Gets the cache source of the image. It indicates from which layer of cache this image is retrieved.
    /// If the image is just downloaded from network, `.none` will be returned.
    public let cacheType: CacheType
    
    /// The `Source` from which the retrieve task begins.
    public let source: Source
}

/// Main manager class of Kingfisher. It connects Kingfisher downloader and cache,
/// to provide a set of convenience methods to use Kingfisher for tasks.
/// You can use this class to retrieve an image via a specified URL from web or cache.
/// KingfisherManager 类
public class KingfisherManager {
    
    /// Represents a shared manager used across Kingfisher.
    /// Use this instance for getting or storing images with Kingfisher.
    public static let shared = KingfisherManager()
    
    /// The `ImageCache` used by this manager. It is `ImageCache.default` by default.
    /// If a cache is specified in `KingfisherManager.defaultOptions`, the value in `defaultOptions` will be
    /// used instead.
    /// 缓存
    public var cache: ImageCache
    
    /// The `ImageDownloader` used by this manager. It is `ImageDownloader.default` by default.
    /// If a downloader is specified in `KingfisherManager.defaultOptions`, the value in `defaultOptions` will be
    /// used instead.
    /// 下载器
    public var downloader: ImageDownloader
    
    /// Default options used by the manager. This option will be used in
    /// Kingfisher manager related methods, as well as all view extension methods.
    /// You can also passing other options for each image task by sending an `options` parameter
    /// to Kingfisher's APIs. The per image options will overwrite the default ones,
    /// if the option exists in both.
    /// 默认请求设置
    public var defaultOptions = KingfisherOptionsInfo.empty
    
    // Use `defaultOptions` to overwrite the `downloader` and `cache`.
    private var currentDefaultOptions: KingfisherOptionsInfo {
        return [.downloader(downloader), .targetCache(cache)] + defaultOptions
    }
    
    /// 进度队列
    private let processingQueue: CallbackQueue
    
    private convenience init() {
        self.init(downloader: .default, cache: .default)
    }
    
    init(downloader: ImageDownloader, cache: ImageCache) {
        self.downloader = downloader
        self.cache = cache
        
        let processQueueName = "com.onevcat.Kingfisher.KingfisherManager.processQueue.\(UUID().uuidString)"
        processingQueue = .dispatch(DispatchQueue(label: processQueueName))
    }
    
    /// Gets an image from a given resource.
    ///
    /// - Parameters:
    ///   - resource: The `Resource` object defines data information like key or URL.
    ///   - options: Options to use when creating the animated image.
    ///   - progressBlock: Called when the image downloading progress gets updated. If the response does not contain an
    ///                    `expectedContentLength`, this block will not be called. `progressBlock` is always called in
    ///                    main queue.
    ///   - completionHandler: Called when the image retrieved and set finished. This completion handler will be invoked
    ///                        from the `options.callbackQueue`. If not specified, the main queue will be used.
    /// - Returns: A task represents the image downloading. If there is a download task starts for `.network` resource,
    ///            the started `DownloadTask` is returned. Otherwise, `nil` is returned.
    ///
    /// - Note:
    ///    This method will first check whether the requested `resource` is already in cache or not. If cached,
    ///    it returns `nil` and invoke the `completionHandler` after the cached image retrieved. Otherwise, it
    ///    will download the `resource`, store it in cache, then call `completionHandler`.
    ///
    @discardableResult
    public func retrieveImage(
        with resource: Resource,
        options: KingfisherOptionsInfo? = nil,
        progressBlock: DownloadProgressBlock? = nil,
        completionHandler: ((Result<RetrieveImageResult, KingfisherError>) -> Void)?) -> DownloadTask?
    {
        let source = Source.network(resource)
        return retrieveImage(
            with: source, options: options, progressBlock: progressBlock, completionHandler: completionHandler
        )
    }
    
    /// Gets an image from a given resource.
    ///
    /// - Parameters:
    ///   - source: The `Source` object defines data information from network or a data provider.
    ///   - options: Options to use when creating the animated image.
    ///   - progressBlock: Called when the image downloading progress gets updated. If the response does not contain an
    ///                    `expectedContentLength`, this block will not be called. `progressBlock` is always called in
    ///                    main queue.
    ///   - completionHandler: Called when the image retrieved and set finished. This completion handler will be invoked
    ///                        from the `options.callbackQueue`. If not specified, the main queue will be used.
    /// - Returns: A task represents the image downloading. If there is a download task starts for `.network` resource,
    ///            the started `DownloadTask` is returned. Otherwise, `nil` is returned.
    ///
    /// - Note:
    ///    This method will first check whether the requested `source` is already in cache or not. If cached,
    ///    it returns `nil` and invoke the `completionHandler` after the cached image retrieved. Otherwise, it
    ///    will try to load the `source`, store it in cache, then call `completionHandler`.
    ///
    public func retrieveImage(
        with source: Source,
        options: KingfisherOptionsInfo? = nil,
        progressBlock: DownloadProgressBlock? = nil,
        completionHandler: ((Result<RetrieveImageResult, KingfisherError>) -> Void)?) -> DownloadTask?
    {
        let options = currentDefaultOptions + (options ?? .empty)
        return retrieveImage(
            with: source,
            options: KingfisherParsedOptionsInfo(options),
            progressBlock: progressBlock,
            completionHandler: completionHandler)
    }
    
    ///检索图片
    func retrieveImage(
        with source: Source,
        options: KingfisherParsedOptionsInfo,
        progressBlock: DownloadProgressBlock? = nil,
        completionHandler: ((Result<RetrieveImageResult, KingfisherError>) -> Void)?) -> DownloadTask?
    {
        /// 是否强制刷新
        if options.forceRefresh {
            /// 从网络下载 并缓存图片
            return loadAndCacheImage(
                source: source, options: options, progressBlock: progressBlock, completionHandler: completionHandler)
        } else {
            /// 从cache 检索图片 loadedFromCache == true表示c缓存中存在 否则 缓存中不存在
            let loadedFromCache = retrieveImageFromCache(
                source: source,
                options: options,
                completionHandler: completionHandler)
            
            if loadedFromCache {
                return nil
            }
            
            /// 如果设置了只从缓存中读取 ，loadedFromCache == false （缓存中又没有） 此时执行completionHandler 并且failure
            if options.onlyFromCache {
                let error = KingfisherError.cacheError(reason: .imageNotExisting(key: source.cacheKey))
                completionHandler?(.failure(error))
                return nil
            }
            
            /// 从网络下载 并缓存图片
            return loadAndCacheImage(
                source: source, options: options, progressBlock: progressBlock, completionHandler: completionHandler)
        }
    }
    
    func provideImage(
        provider: ImageDataProvider,
        options: KingfisherParsedOptionsInfo,
        completionHandler: ((Result<ImageLoadingResult, KingfisherError>) -> Void)?)
    {
        provider.data { result in
            switch result {
            case .success(let data):
                (options.processingQueue ?? self.processingQueue).execute {
                    let processor = options.processor
                    let processingItem = ImageProcessItem.data(data)
                    guard let image = processor.process(item: processingItem, options: options) else {
                        options.callbackQueue.execute {
                            completionHandler?(
                                .failure(
                                    .processorError(reason: .processingFailed(processor: processor, item: processingItem))
                                )
                            )
                        }
                        return
                    }
                    
                    let result = ImageLoadingResult(image: image, url: nil, originalData: data)
                    options.callbackQueue.execute { completionHandler?(.success(result)) }
                }
            case .failure(let error):
                options.callbackQueue.execute {
                    completionHandler?(
                        .failure(.imageSettingError(reason: .dataProviderError(provider: provider, error: error)))
                    )
                }
                
            }
        }
    }
    
    /// 从网络下载图片 并缓存起来
    @discardableResult
    func loadAndCacheImage(
        source: Source,
        options: KingfisherParsedOptionsInfo,
        progressBlock: DownloadProgressBlock? = nil,
        completionHandler: ((Result<RetrieveImageResult, KingfisherError>) -> Void)?) -> DownloadTask?
    {
        /// 缓存图片
        func cacheImage(_ result: Result<ImageLoadingResult, KingfisherError>)
        {
            switch result {
            case .success(let value):
                // Add image to cache.
                let targetCache = options.targetCache ?? self.cache
                targetCache.store(
                    value.image,
                    original: value.originalData,
                    forKey: source.cacheKey,
                    options: options,
                    toDisk: !options.cacheMemoryOnly)
                {
                    _ in
                    if options.waitForCache {
                        let result = RetrieveImageResult(image: value.image, cacheType: .none, source: source)
                        completionHandler?(.success(result))
                    }
                }
                
                // Add original image to cache if necessary.
                let needToCacheOriginalImage = options.cacheOriginalImage &&
                    options.processor != DefaultImageProcessor.default
                if needToCacheOriginalImage {
                    let originalCache = options.originalCache ?? targetCache
                    originalCache.storeToDisk(
                        value.originalData,
                        forKey: source.cacheKey,
                        processorIdentifier: DefaultImageProcessor.default.identifier,
                        expiration: options.diskCacheExpiration)
                }
                
                if !options.waitForCache {
                    let result = RetrieveImageResult(image: value.image, cacheType: .none, source: source)
                    completionHandler?(.success(result))
                }
            case .failure(let error):
                completionHandler?(.failure(error))
            }
        }
        
        switch source {
        case .network(let resource): /// 从网络下载
            let downloader = options.downloader ?? self.downloader
            return downloader.downloadImage(
                with: resource.downloadURL,
                options: options,
                progressBlock: progressBlock,
                completionHandler: cacheImage)
        case .provider(let provider): /// 从本地读取
            provideImage(provider: provider, options: options, completionHandler: cacheImage)
            return nil
        }
    }
    
    /// Retrieves image from memory or disk cache.
    ///
    /// - Parameters:
    ///   - source: The target source from which to get image.
    ///   - key: The key to use when caching the image.
    ///   - url: Image request URL. This is not used when retrieving image from cache. It is just used for
    ///          `RetrieveImageResult` callback compatibility.
    ///   - options: Options on how to get the image from image cache.
    ///   - completionHandler: Called when the image retrieving finishes, either with succeeded
    ///                        `RetrieveImageResult` or an error.
    /// - Returns: `true` if the requested image or the original image before being processed is existing in cache.
    ///            Otherwise, this method returns `false`.
    ///
    /// - Note:
    ///    The image retrieving could happen in either memory cache or disk cache. The `.processor` option in
    ///    `options` will be considered when searching in the cache. If no processed image is found, Kingfisher
    ///    will try to check whether an original version of that image is existing or not. If there is already an
    ///    original, Kingfisher retrieves it from cache and processes it. Then, the processed image will be store
    ///    back to cache for later use.
    /// 从缓存中获取图片
    func retrieveImageFromCache(
        source: Source,
        options: KingfisherParsedOptionsInfo,
        completionHandler: ((Result<RetrieveImageResult, KingfisherError>) -> Void)?) -> Bool
    {
        // 1. Check whether the image was already in target cache. If so, just get it.
        /// 检查image 是否已经存在缓存中了 如果存在直接获取
        let targetCache = options.targetCache ?? cache
        let key = source.cacheKey
        
        let targetImageCached = targetCache.imageCachedType(
            forKey: key, processorIdentifier: options.processor.identifier)
        
        let validCache = targetImageCached.cached &&
            (options.fromMemoryCacheOrRefresh == false || targetImageCached == .memory)
        if validCache {
            targetCache.retrieveImage(forKey: key, options: options) { result in
                if let image = result.value?.image {
                    let value = result.map {
                        RetrieveImageResult(image: image, cacheType: $0.cacheType, source: source)
                    }
                    completionHandler?(value)
                } else {
                    completionHandler?(.failure(KingfisherError.cacheError(reason: .imageNotExisting(key: key))))
                }
            }
            return true
        }
        
        // 2. Check whether the original image exists. If so, get it, process it, save to storage and return.
        /// 检查原始图像是否存在。如果是这样的话，得到它，处理它，保存到存储并返回。
        let originalCache = options.originalCache ?? targetCache
        // No need to store the same file in the same cache again.
        if originalCache === targetCache && options.processor == DefaultImageProcessor.default {
            return false
        }
        
        // Check whether the unprocessed image existing or not.
        let originalImageCached = originalCache.imageCachedType(
            forKey: key, processorIdentifier: DefaultImageProcessor.default.identifier).cached
        if originalImageCached {
            // Now we are ready to get found the original image from cache. We need the unprocessed image, so remove
            // any processor from options first.
            var optionsWithoutProcessor = options
            optionsWithoutProcessor.processor = DefaultImageProcessor.default
            originalCache.retrieveImage(forKey: key, options: optionsWithoutProcessor) { result in
                if let image = result.value?.image {
                    let processor = options.processor
                    (options.processingQueue ?? self.processingQueue).execute {
                        let item = ImageProcessItem.image(image)
                        guard let processedImage = processor.process(item: item, options: options) else {
                            let error = KingfisherError.processorError(
                                reason: .processingFailed(processor: processor, item: item))
                            completionHandler?(.failure(error))
                            return
                        }
                        
                        var cacheOptions = options
                        cacheOptions.callbackQueue = .untouch
                        targetCache.store(
                            processedImage,
                            forKey: key,
                            options: cacheOptions,
                            toDisk: !options.cacheMemoryOnly)
                        {
                            _ in
                            if options.waitForCache {
                                let value = RetrieveImageResult(image: processedImage, cacheType: .none, source: source)
                                completionHandler?(.success(value))
                            }
                        }
                        
                        if !options.waitForCache {
                            let value = RetrieveImageResult(image: processedImage, cacheType: .none, source: source)
                            completionHandler?(.success(value))
                        }
                    }
                } else {
                    // This should not happen actually, since we already confirmed `originalImageCached` is `true`.
                    // Just in case...
                    completionHandler?(.failure(KingfisherError.cacheError(reason: .imageNotExisting(key: key))))
                }
            }
            return true
        }
        
        return false
        
    }
}

