export class SearchHistory {
  keyword: string = ''
  searchType: string = 'illust'
  timestamp: number = Date.now()

  constructor(options: Partial<SearchHistory> = {}) {
    this.keyword = options.keyword ?? ''
    this.searchType = options.searchType ?? 'illust'
    this.timestamp = options.timestamp ?? Date.now()
  }
}
