import { router } from '@kit.ArkUI';
import { apiService } from '../../network/ApiService';
import { IllustWaterfall, IllustListPage, parseIllustListPage } from '../../components/illust/IllustWaterfall';

interface TagSearchParams {
  keyword: string
}

@Entry
@Component
struct TagSearchPage {
  @State keyword: string = ''

  aboutToAppear() {
    let params = router.getParams() as TagSearchParams
    if (params && params.keyword) {
      this.keyword = params.keyword
    }
  }

  private async fetchFirst(): Promise<IllustListPage> {
    let response = await apiService.searchIllusts(this.keyword)
    return parseIllustListPage(response)
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

      IllustWaterfall({ fetchFirst: (): Promise<IllustListPage> => this.fetchFirst() })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
