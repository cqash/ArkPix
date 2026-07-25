import { apiService } from '../../network/ApiService';
import { IllustWaterfall, IllustListPage, parseIllustListPage } from '../../components/illust/IllustWaterfall';
import { getDbService } from '../../services/DatabaseService';

@Component
export struct RecomPage {
  private async fetchFirst(): Promise<IllustListPage> {
    let db = await getDbService()
    try {
      let response = await apiService.getRecommendedIllusts()
      let page = parseIllustListPage(response)
      if (page.illusts.length > 0) {
        await db.setRecommendCache(JSON.stringify(response as object))
      }
      return page
    } catch (e) {
      // 网络失败回退缓存
      let cached = await db.getRecommendCache()
      if (cached) {
        return parseIllustListPage(JSON.parse(cached))
      }
      throw new Error('推荐列表加载失败: ' + e)
    }
  }

  build() {
    IllustWaterfall({ fetchFirst: (): Promise<IllustListPage> => this.fetchFirst() })
  }
}
