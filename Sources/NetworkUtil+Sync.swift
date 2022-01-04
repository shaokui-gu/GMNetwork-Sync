//
//  NetworkUtil+.swift
//  Polytime
//
//  Created by gavin on 2022/1/4.
//  Copyright © 2022 cn.kroknow. All rights reserved.
//

import Foundation
import Alamofire
import GMNetwork

/// 请求结果回调
public typealias GMSyncResponseHandler = (GMNetworkRequest, AutoreleasingUnsafeMutablePointer<GMNetworkResponse?>, AutoreleasingUnsafeMutablePointer<GMNetworkException?>, AFDataResponse<Data>) -> Void

/// 拦截器
open class GMSyncNetworkIntercepter : Interceptor {
    public let responseHandler: GMSyncResponseHandler
    public init(adaptHandler: @escaping AdaptHandler, responseHandler:@escaping GMSyncResponseHandler, retryHandler: @escaping RetryHandler) {
        self.responseHandler = responseHandler
        super.init(adaptHandler: adaptHandler, retryHandler: retryHandler)
    }
}

public extension GMNetworkUtil {
    
    struct GMNetworkAssociateKeys {
        static var syncIntercepterKey = "sync_intercepter_key"
    }
    
    var syncIntercepter:GMSyncNetworkIntercepter? {
        set {
            objc_setAssociatedObject(self, &GMNetworkAssociateKeys.syncIntercepterKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
        get {
            return objc_getAssociatedObject(self, &GMNetworkAssociateKeys.syncIntercepterKey) as? GMSyncNetworkIntercepter
        }
    }
    
    /// 同步请求
    /// - Parameter request: 请求体
    /// - Returns: 请求任务
    func syncRequest(request:GMNetworkRequest) throws -> Any? {
        let semaphore = DispatchSemaphore.init(value: 0)
        let url = request.url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        var dataRequest:DataRequest?
        var dataResponse:GMNetworkResponse? = nil
        var dataException:GMNetworkException? = nil
        var headers:[String : String] = [:]
        if let requestHeaders = request.headers {
            headers.merge(requestHeaders) { new, old in
                return new
            }
        }
        if request.dataArray.count == 0 {
            dataRequest = AF.request(url, method: request.method, parameters: request.parameters, encoder: JSONParameterEncoder.default, headers: HTTPHeaders(headers), interceptor: self.intercapter)
        } else {
            dataRequest = AF.upload(multipartFormData: { formData in
                for dataItem in request.dataArray {
                    if let url = dataItem.fileURL {
                        formData.append(url, withName: dataItem.fileKey)
                    } else if let data = dataItem.data {
                        formData.append(data, withName: dataItem.fileKey, fileName: dataItem.fileName, mimeType: dataItem.mineType)
                    }
                }
                if let params = request.parameters {
                    for (key, value) in params.dict {
                        let str:String = value as! String
                        let _datas:Data = str.data(using: String.Encoding.utf8)!
                        formData.append(_datas, withName: key)
                    }
                }
                
            }, to: url, method: request.method, headers: HTTPHeaders(headers), interceptor: self.intercapter)
        }
                
        dataRequest!.responseData {[weak self] (response) in
            self?.syncIntercepter?.responseHandler(request, &dataResponse, &dataException, response)
            semaphore.signal()
        }
        dataRequest?.resume()
        semaphore.wait()
        if let exception = dataException {
            throw exception
        }
        return dataResponse
    }

    /// 同步GET 请求
    /// - Parameters:
    ///   - path: url 路径
    ///   - delegate: 代理
    @discardableResult
    func SYNC_GET(_ url:String, _ serializer:GMNetworkResponseSerializer? = nil) throws -> Any? {
        return try self.syncRequest(request:GMNetworkRequest(url, method: .get, serializer:serializer))
    }

    /// 同步 POST 请求
    /// - Parameters:
    ///   - path: url 路径
    ///   - parameters: 参数
    ///   - delegate: 代理
    @discardableResult
    func SYNC_POST(_ url:String, parameters:Dictionary<String, Encodable>? = nil, _ serializer:GMNetworkResponseSerializer? = nil) throws -> Any? {
        return try self.syncRequest(request:GMNetworkRequest(url, method: .post, parameters: parameters == nil ? nil : Parameters.init(dict: parameters!), serializer:serializer))
    }

    
    /// 同步PUT 请求
    /// - Parameters:
    ///   - path: url 路径
    ///   - parameters: 参数
    ///   - delegate: 代理
    @discardableResult
    func SYNC_PUT(_ url:String, parameters:Dictionary<String, Encodable>? = nil, _ serializer:GMNetworkResponseSerializer? = nil) -> GMNetworkTask {
        return self.request(request:GMNetworkRequest(url, method: .put, parameters: parameters == nil ? nil : Parameters.init(dict: parameters!), serializer:serializer))
    }

    /// 同步 DELETE 请求
    /// - Parameters:
    ///   - path: url 路径
    ///   - delegate: 代理
    @discardableResult
    func SYNC_DELETE(_ url:String, parameters:Dictionary<String, Encodable>? = nil, _ serializer:GMNetworkResponseSerializer? = nil) throws -> Any? {
        return try self.syncRequest(request:GMNetworkRequest(url, method: .delete, parameters:parameters == nil ? nil : Parameters.init(dict: parameters!), serializer:serializer))
    }

    /// 同步 UPLOAD 请求
    /// - Parameters:
    ///   - path: url 路径
    ///   - delegate: 代理
    @discardableResult
    func ASYNC_UPLOAD(_ url:String, dataArray:[GMNetworkFormData], parameters:Dictionary<String, Encodable>? = nil, method:HTTPMethod = .upload,  _ serializer:GMNetworkResponseSerializer? = nil) throws -> Any? {
        return try self.syncRequest(request: GMNetworkRequest(url, method: method, parameters:parameters == nil ? nil : Parameters.init(dict: parameters!) ,dataArray: dataArray, serializer: serializer))
    }

}
