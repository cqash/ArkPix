import { apiService } from '../../network/ApiService';
import { Illust } from '../../models/Illust';
import { userSettingStore } from '../../stores/UserSettingStore';

interface RankingResponse {
  illusts: Object[]
  next_url: string
}

@Component
export struct RankPage {
  @State illustList: Illust[] = []
  @State isLoading: boolean = false
  @State isRefreshing: boolean = false
  @State selectedMode: string = 'day'
  @State selectedDate: string = ''

  aboutToAppear() {
    let yesterday = new Date()
    yesterday.setDate(yesterday.getDate() - 1)
    this.selectedDate = yesterday.toISOString().split('T')[0].replace(/-/g, '')
    this.loadData()
  }

  async loadData() {
    if (this.isLoading) { return }
    this.isLoading = true
    try {
      let response = await apiService.getRankingIllusts(this.selectedMode, this.selectedDate)
      let illusts = (response as RankingResponse).illusts
      if (illusts) {
        this.illustList = illusts.map((item: Object) => new Illust(item as Partial<Illust>))
      }
    } catch (e) {
      console.error('Load ranking failed: ' + e)
    } finally {
      this.isLoading = false
    }
  }

  @Builder
  IllustCard(item: Illust) {
    Column() {
      Image(item.imageUrls.medium)
        .width('100%')
        .aspectRatio(1)
        .objectFit(ImageFit.Cover)
        .borderRadius(8)
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
  }

  build() {
    Column() {
      Row() {
        Text('日榜')
          .fontSize(14)
          .fontColor(this.selectedMode === 'day' ? '#0096FA' : '#333333')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .onClick(() => { this.selectedMode = 'day'; this.loadData() })
        Text('周榜')
          .fontSize(14)
          .fontColor(this.selectedMode === 'week' ? '#0096FA' : '#333333')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .onClick(() => { this.selectedMode = 'week'; this.loadData() })
        Text('月榜')
          .fontSize(14)
          .fontColor(this.selectedMode === 'month' ? '#0096FA' : '#333333')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .onClick(() => { this.selectedMode = 'month'; this.loadData() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 8, bottom: 8 })

      Refresh({ refreshing: $$this.isRefreshing, offset: 64, friction: 100 }) {
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
      .onRefreshing(() => { this.loadData() })
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}
