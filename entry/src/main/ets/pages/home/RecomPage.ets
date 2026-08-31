import { apiService } from '../../network/ApiService';
import { IllustWaterfall, IllustListPage, parseIllustListPage } from '../../components/illust/IllustWaterfall';
import { getDbService } from '../../services/DatabaseService';
import { getStrf } from '../../utils/I18nUtils';

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
      throw new Error(getStrf($r('app.string.home_recom_load_failed'), String(e)))
    }
  }

  build() {
    IllustWaterfall({ fetchFirst: (): Promise<IllustListPage> => this.fetchFirst() })
  }
}
