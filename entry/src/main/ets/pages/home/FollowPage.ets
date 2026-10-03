import { apiService } from '../../network/ApiService';
import { IllustWaterfall, IllustListPage, parseIllustListPage } from '../../components/illust/IllustWaterfall';

@Component
export struct FollowPage {
  /** 底栏 Tab 再点回顶：仅响应 tabIndex=1 的令牌 */
  @StorageLink('tabRetapToken') @Watch('onTabRetap') tabRetapToken: string = ''
  @State scrollTopToken: number = 0

  onTabRetap() {
    let idx = this.tabRetapToken.indexOf(':')
    if (idx <= 0) {
      return
    }
    if (Number(this.tabRetapToken.substring(0, idx)) === 1) {
      this.scrollTopToken += 1
    }
  }

  private async fetchFirst(): Promise<IllustListPage> {
    // 首屏返回真实 next_url，续页由容器经 fetchNext 驱动（修复旧版加载更多重复拉首屏）
    let response = await apiService.getFollowIllusts('public')
    return parseIllustListPage(response)
  }

  build() {
    IllustWaterfall({
      fetchFirst: (): Promise<IllustListPage> => this.fetchFirst(),
      scrollTopToken: this.scrollTopToken,
      bottomInset: 72
    })
  }
}
