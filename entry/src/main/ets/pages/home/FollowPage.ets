import { apiService } from '../../network/ApiService';
import { IllustWaterfall, IllustListPage, parseIllustListPage } from '../../components/illust/IllustWaterfall';

@Component
export struct FollowPage {
  private async fetchFirst(): Promise<IllustListPage> {
    // 首屏返回真实 next_url，续页由容器经 fetchNext 驱动（修复旧版加载更多重复拉首屏）
    let response = await apiService.getFollowIllusts('public')
    return parseIllustListPage(response)
  }

  build() {
    IllustWaterfall({ fetchFirst: (): Promise<IllustListPage> => this.fetchFirst() })
  }
}
