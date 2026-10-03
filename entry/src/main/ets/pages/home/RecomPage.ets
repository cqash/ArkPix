import { apiService } from '../../network/ApiService';
import { IllustWaterfall, IllustListPage, parseIllustListPage } from '../../components/illust/IllustWaterfall';
import { getDbService } from '../../services/DatabaseService';
import { getStrf } from '../../utils/I18nUtils';

@Component
export struct RecomPage {
  /** 底栏 Tab 再点回顶：仅响应 tabIndex=0 的令牌 */
  @StorageLink('tabRetapToken') @Watch('onTabRetap') tabRetapToken: string = ''
  @State scrollTopToken: number = 0

  onTabRetap() {
    let idx = this.tabRetapToken.indexOf(':')
    if (idx <= 0) {
      return
    }
    if (Number(this.tabRetapToken.substring(0, idx)) === 0) {
      this.scrollTopToken += 1
    }
  }

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

  /** 冷启动缓存源：读取 DB 推荐缓存供瀑布流先渲染，无缓存/解析失败返回 null */
  private async fetchCached(): Promise<IllustListPage | null> {
    try {
      let db = await getDbService()
      let cached = await db.getRecommendCache()
      if (cached) {
        return parseIllustListPage(JSON.parse(cached))
      }
    } catch (e) {
      console.error('RecomPage read cache failed: ' + e)
    }
    return null
  }

  build() {
    IllustWaterfall({
      fetchFirst: (): Promise<IllustListPage> => this.fetchFirst(),
      fetchCached: (): Promise<IllustListPage | null> => this.fetchCached(),
      scrollTopToken: this.scrollTopToken,
      bottomInset: 72
    })
  }
}
