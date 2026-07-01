import { router } from '@kit.ArkUI';
import { apiService } from '../../network/ApiService';
import { Illust, ImageUrls } from '../../models/Illust';
import { userSettingStore } from '../../stores/UserSettingStore';
import { CachedImage } from '../../components/common/CachedImage';
import { ErrorView } from '../../components/common/CommonViews';

interface TagSearchParams {
  keyword: string
}

interface SearchResponse {
  illusts: Object[]
}

function pickPreviewUrl(urls: ImageUrls, quality: number): string {
  if (quality === 0) {
    return urls.squareMedium || urls.medium || urls.large
  }
  if (quality === 1) {
    return urls.medium || urls.large || urls.original
  }
  return urls.large || urls.medium || urls.original
}

@Entry
@Component
struct TagSearchPage {
  @State keyword: string = ''
  @State illustList: Illust[] = []
  @State isLoading: boolean = false
  @State errorMessage: string = ''

  aboutToAppear() {
    let params = router.getParams() as TagSearchParams
    if (params && params.keyword) {
      this.keyword = params.keyword
      this.search()
    }
  }

  async search() {
    this.isLoading = true
    this.errorMessage = ''
    try {
      let response = await apiService.searchIllusts(this.keyword)
      let illusts = (response as SearchResponse).illusts
      if (illusts) {
        this.illustList = illusts.map((item: Object) => Illust.fromJson(item))
      }
    } catch (e) {
      this.errorMessage = '搜索失败: ' + e
      console.error('Tag search failed: ' + e)
    } finally {
      this.isLoading = false
    }
  }

  @Builder
  IllustCard(item: Illust) {
    Column() {
      CachedImage({ url: pickPreviewUrl(item.imageUrls, userSettingStore.getSettings().previewQuality) })
      Text(item.title)
        .fontSize(12)
        .fontColor('#333333')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 })
      Text(item.user.name)
        .fontSize(10)
        .fontColor('#999999')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(4)
    .onClick(() => {
      router.pushUrl({ url: 'pages/detail/IllustDetailPage', params: { illustId: item.id } })
    })
  }

  build() {
    Column() {
      Row() {
        Button('返回')
          .fontSize(14)
          .backgroundColor('#F5F5F5')
          .fontColor('#333333')
          .onClick(() => { router.back() })
        Text(this.keyword)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Blank()
          .width(60)
      }
      .width('100%')
      .height(48)
      .padding({ left: 8, right: 8 })
      .backgroundColor('#FFFFFF')

      if (this.errorMessage && this.illustList.length === 0) {
        ErrorView({ message: this.errorMessage, onRetry: () => { this.search() } })
      } else if (this.isLoading) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color('#0096FA')
          .margin({ top: 32 })
      } else {
        List({ space: 8 }) {
          ForEach(this.illustList, (item: Illust) => {
            ListItem() {
              this.IllustCard(item)
            }
          }, (item: Illust) => item.id.toString())
        }
        .lanes(userSettingStore.getSettings().crossCount)
        .padding(8)
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
