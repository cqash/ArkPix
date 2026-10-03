import { apiService } from '../../network/ApiService';
import { IllustWaterfall, IllustListPage, parseIllustListPage } from '../../components/illust/IllustWaterfall';
import { getDbService } from '../../services/DatabaseService';
import { AppSettings } from '../../models/AppSettings';
import { getStrf } from '../../utils/I18nUtils';

interface RankModeItem {
  labelRes: Resource
  mode: string
  r18: boolean
}

const RANK_MODES: RankModeItem[] = [
  { labelRes: $r('app.string.home_rank_day'), mode: 'day', r18: false },
  { labelRes: $r('app.string.home_rank_week'), mode: 'week', r18: false },
  { labelRes: $r('app.string.home_rank_month'), mode: 'month', r18: false },
  { labelRes: $r('app.string.home_rank_rookie'), mode: 'week_rookie', r18: false },
  { labelRes: $r('app.string.home_rank_original'), mode: 'week_original', r18: false },
  { labelRes: $r('app.string.home_rank_male'), mode: 'day_male', r18: false },
  { labelRes: $r('app.string.home_rank_female'), mode: 'day_female', r18: false },
  { labelRes: $r('app.string.home_rank_day_r18'), mode: 'day_r18', r18: true },
  { labelRes: $r('app.string.home_rank_male_r18'), mode: 'day_male_r18', r18: true },
  { labelRes: $r('app.string.home_rank_female_r18'), mode: 'day_female_r18', r18: true },
  { labelRes: $r('app.string.home_rank_week_r18'), mode: 'week_r18', r18: true },
  { labelRes: $r('app.string.home_rank_week_r18g'), mode: 'week_r18g', r18: true }
]

@Component
export struct RankPage {
  @State selectedMode: string = 'day'
  @State selectedDate: string = ''
  @State reloadToken: number = 0
  /** 底栏 Tab 再点回顶：仅响应 tabIndex=2 的令牌（单瀑布流天然只回顶当前榜单） */
  @StorageLink('tabRetapToken') @Watch('onTabRetap') tabRetapToken: string = ''
  @State scrollTopToken: number = 0
  @StorageLink('appSettings') appSettings: AppSettings = new AppSettings()

  onTabRetap() {
    let idx = this.tabRetapToken.indexOf(':')
    if (idx <= 0) {
      return
    }
    if (Number(this.tabRetapToken.substring(0, idx)) === 2) {
      this.scrollTopToken += 1
    }
  }

  aboutToAppear() {
    let yesterday = new Date()
    yesterday.setDate(yesterday.getDate() - 1)
    this.selectedDate = yesterday.toISOString().split('T')[0]
  }

  private async fetchFirst(): Promise<IllustListPage> {
    let db = await getDbService()
    try {
      let response = await apiService.getRankingIllusts(this.selectedMode, this.selectedDate)
      let page = parseIllustListPage(response)
      if (page.illusts.length > 0) {
        await db.setRankingCache(this.selectedMode, this.selectedDate, JSON.stringify(response as object))
      }
      return page
    } catch (e) {
      let cached = await db.getRankingCache(this.selectedMode, this.selectedDate)
      if (cached) {
        return parseIllustListPage(JSON.parse(cached))
      }
      throw new Error(getStrf($r('app.string.home_rank_load_failed'), String(e)))
    }
  }

  selectMode(mode: string) {
    if (this.selectedMode === mode) {
      return
    }
    this.selectedMode = mode
    this.reloadToken++
  }

  showDatePicker() {
    let yesterday = new Date()
    yesterday.setDate(yesterday.getDate() - 1)
    let selected = new Date(this.selectedDate + 'T00:00:00')
    DatePickerDialog.show({
      start: new Date('2016-01-01T00:00:00'),
      end: yesterday,
      selected: selected,
      onDateAccept: (value: Date) => {
        let year = value.getFullYear()
        let month = (value.getMonth() + 1).toString().padStart(2, '0')
        let day = value.getDate().toString().padStart(2, '0')
        this.selectedDate = year + '-' + month + '-' + day
        this.reloadToken++
      }
    })
  }

  build() {
    Column() {
      Scroll() {
        Row() {
          ForEach(RANK_MODES, (item: RankModeItem) => {
            if (!item.r18 || this.appSettings.showR18Rank) {
              Text(item.labelRes)
                .fontSize(14)
                .fontColor(this.selectedMode === item.mode ? '#0096FA' : '#333333')
                .fontWeight(this.selectedMode === item.mode ? FontWeight.Bold : FontWeight.Normal)
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .onClick(() => { this.selectMode(item.mode) })
            }
          }, (item: RankModeItem) => item.mode)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .padding({ top: 8, bottom: 8 })

      Row() {
        Text(getStrf($r('app.string.home_rank_date'), this.selectedDate))
          .fontSize(12)
          .fontColor('#0096FA')
          .padding({ left: 16, right: 16, top: 4, bottom: 4 })
          .backgroundColor('#E6F4FF')
          .borderRadius(12)
          .onClick(() => { this.showDatePicker() })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ left: 16, right: 16, bottom: 4 })

      IllustWaterfall({
        fetchFirst: (): Promise<IllustListPage> => this.fetchFirst(),
        reloadToken: this.reloadToken,
        scrollTopToken: this.scrollTopToken,
        bottomInset: 72
      })
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}
