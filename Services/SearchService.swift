import Foundation

// 搜索服务：将查询请求委托给索引存储
public final class SearchService: SearchServiceProtocol {
    private let store: IndexStoreProtocol
    public init(store: IndexStoreProtocol) { self.store = store }
    public func search(_ query: String, filters: SearchFilters, limit: Int) -> [ClipItem] {
        store.query(filters, query: query, limit: limit, offset: 0)
    }
}