import { apiService } from '../../network/ApiService';

interface NovelItem {
  id: number
  title: string
}

interface NovelResponse {
  novels: NovelItem[]
}

@Component
export struct NovelPage {
  @State novelList: NovelItem[] = []
  @State isLoading: boolean = false

  aboutToAppear() {
    this.loadData()
  }

  async loadData() {
    this.isLoading = true
    try {
      let response = await apiService.getNovelRecommended()
      let novels = (response as NovelResponse).novels
      if (novels) {
        this.novelList = novels
      }
    } catch (e) {
      console.error('Load novel failed: ' + e)
    } finally {
      this.isLoading = false
    }
  }

  build() {
    Column() {
      if (this.isLoading) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color('#0096FA')
      } else {
        List() {
          ForEach(this.novelList, (item: NovelItem) => {
            ListItem() {
              Row() {
                Text(item.title || '')
                  .fontSize(14)
                  .fontColor('#333333')
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#FFFFFF')
            }
          }, (item: NovelItem) => (item.id || 0).toString())
        }
        .divider({ strokeWidth: 0.5, color: '#EEEEEE' })
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
  }
}
