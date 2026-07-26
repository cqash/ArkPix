import { router } from '@kit.ArkUI';
import { apiService } from '../../network/ApiService';
import { accountStore } from '../../stores/AccountStore';
import { Illust } from '../../models/Illust';
import {
  IllustWaterfall,
  IllustListPage,
  parseIllustListPage,
  compareArrivalReverse
} from '../../components/illust/IllustWaterfall';

/** 收藏排序模式：bookmarkDesc 默认（接口原始序）；仅存 @State 不持久化 */
type BookmarkSortMode = 'bookmarkDesc' | 'bookmarkAsc' | 'uploadDesc' | 'totalBookmarksDesc'

@Entry
@Component
struct BookmarkPage {
  @State restrict: string = 'public'
  @State reloadToken: number = 0
  @State loginError: string = ''
  @State sortMode: BookmarkSortMode = 'bookmarkDesc'
  @State compareToken: number = 0
  @State sortMenuShown: boolean = false

  aboutToAppear() {
    if (accountStore.getCurrentUserId() === 0) {
      this.loginError = '未登录，无法查看收藏'
    }
  }

  private async fetchFirst(): Promise<IllustListPage> {
    let userId = accountStore.getCurrentUserId()
    if (userId === 0) {
      throw new Error('未登录，无法查看收藏')
    }
    let response = await apiService.getUserBookmarks(userId, this.restrict)
    return parseIllustListPage(response)
  }

  switchRestrict(restrict: string) {
    if (this.restrict === restrict) {
      return
    }
    this.restrict = restrict
    this.reloadToken++
  }

  private currentCompareFn(): ((a: Illust, b: Illust) => number) | undefined {
    if (this.sortMode === 'bookmarkAsc') {
      return compareArrivalReverse
    }
    if (this.sortMode === 'uploadDesc') {
      return (a: Illust, b: Illust): number => b.createDate.localeCompare(a.createDate)
    }
    if (this.sortMode === 'totalBookmarksDesc') {
      return (a: Illust, b: Illust): number => b.totalBookmarks - a.totalBookmarks
    }
    return undefined
  }

  private applySort(mode: BookmarkSortMode): void {
    if (this.sortMode === mode) {
      return
    }
    this.sortMode = mode
    this.compareToken++
  }

  @Builder
  SortMenuItem(label: string, action: () => void) {
    Text(label)
      .fontSize(14)
      .fontColor('#333333')
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .onClick(action)
  }

  @Builder
  SortMenuBuilder() {
    Column() {
      this.SortMenuItem('收藏时间 新→旧（默认）', () => { this.applySort('bookmarkDesc') })
      this.SortMenuItem('收藏时间 旧→新', () => { this.applySort('bookmarkAsc') })
      this.SortMenuItem('上传时间 新→旧', () => { this.applySort('uploadDesc') })
      this.SortMenuItem('收藏数 高→低', () => { this.applySort('totalBookmarksDesc') })
    }
    .width(180)
    .padding({ top: 4, bottom: 4 })
  }

  build() {
    Column() {
      Row() {
        Button('返回')
          .fontSize(14)
          .backgroundColor('#F5F5F5')
          .fontColor('#333333')
          .onClick(() => { router.back() })
        Text('我的收藏')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('排序')
          .fontSize(14)
          .fontColor('#0096FA')
          .width(60)
          .textAlign(TextAlign.End)
          .onClick(() => { this.sortMenuShown = true })
      }
      .width('100%')
      .height(48)
      .padding({ left: 8, right: 8 })
      .backgroundColor('#FFFFFF')
      .bindContextMenu(this.sortMenuShown, this.SortMenuBuilder, {
        onDisappear: () => { this.sortMenuShown = false }
      })

      Row() {
        Text('公开')
          .fontSize(14)
          .fontColor(this.restrict === 'public' ? '#0096FA' : '#333333')
          .fontWeight(this.restrict === 'public' ? FontWeight.Bold : FontWeight.Normal)
          .padding({ left: 24, right: 24, top: 8, bottom: 8 })
          .onClick(() => { this.switchRestrict('public') })
        Text('私密')
          .fontSize(14)
          .fontColor(this.restrict === 'private' ? '#0096FA' : '#333333')
          .fontWeight(this.restrict === 'private' ? FontWeight.Bold : FontWeight.Normal)
          .padding({ left: 24, right: 24, top: 8, bottom: 8 })
          .onClick(() => { this.switchRestrict('private') })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#FFFFFF')

      if (this.loginError) {
        Text(this.loginError)
          .fontSize(14)
          .fontColor('#999999')
          .margin({ top: 32 })
      } else {
        IllustWaterfall({
          fetchFirst: (): Promise<IllustListPage> => this.fetchFirst(),
          reloadToken: this.reloadToken,
          compareFn: this.currentCompareFn(),
          compareToken: this.compareToken
        })
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
