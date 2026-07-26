import { router } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { imageCacheService } from '../../services/ImageCacheService';
import { Illust, Tag } from '../../models/Illust';
import { AppSettings } from '../../models/AppSettings';
import { userSettingStore } from '../../stores/UserSettingStore';
import { BOOKMARK_LOADING, BOOKMARK_DONE } from '../../stores/BookmarkStateStore';
import { IllustDetailStore, DetailRow } from '../../stores/IllustDetailStore';
import { buildPageUrls } from '../../utils/ImageUrlUtils';
import { CachedImage } from '../../components/common/CachedImage';
import { IllustCard } from '../../components/illust/IllustCard';
import { ErrorView, LoadingView } from '../../components/common/CommonViews';

interface RouteParams {
  illustId: number
}

@Entry
@Component
struct IllustDetailPage {
  private store: IllustDetailStore = new IllustDetailStore()
  @State illust: Illust = new Illust()
  @State rows: DetailRow[] = []
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State illustId: number = 0
  @State userAvatarPath: string = ''
  @State revealedR18: boolean = false
  @State bookmarkMenuShown: boolean = false
  @State tagMenuShown: boolean = false
  @State tagMenuTarget: string = ''
  @State saveMenuShown: boolean = false
  @State saveMenuPageIndex: number = 0
  @StorageLink('bookmarkStates') bookmarkStates: Map<number, number> = new Map<number, number>()
  @StorageLink('appSettings') appSettings: AppSettings = new AppSettings()

  aboutToAppear() {
    this.store.uiContext = this.getUIContext()
    let params = router.getParams() as RouteParams
    if (params && params.illustId) {
      this.illustId = params.illustId
      this.loadDetail(params.illustId)
    }
  }

  async loadDetail(id: number, forceRefresh: boolean = false) {
    if (this.rows.length === 0) {
      this.isLoading = true
    }
    this.errorMessage = ''
    let ok = await this.store.load(id, forceRefresh)
    if (ok || this.store.illust.id > 0) {
      this.illust = this.store.illust
      this.rebuildRows()
      this.loadAvatar()
      this.store.loadRelated().then(() => {
        this.rebuildRows()
      }).catch((e: Object) => {
        console.error('Load related failed: ' + e)
      })
    } else {
      this.errorMessage = this.store.errorMessage || '加载失败'
    }
    this.isLoading = false
  }

  private rebuildRows(): void {
    this.rows = this.store.buildRows(userSettingStore.getSettings().detailQuality)
  }

  private async loadAvatar(): Promise<void> {
    let url = this.illust.user.profileImageUrls.medium
    if (url) {
      this.userAvatarPath = await imageCacheService.getLocalPath(url)
    }
  }

  private bookmarkState(): number {
    let state = this.bookmarkStates.get(this.illust.id)
    if (state !== undefined) {
      return state
    }
    return this.illust.isBookmarked ? BOOKMARK_DONE : 0
  }

  private isR18(): boolean {
    return this.illust.xRestrict === 1 || this.illust.xRestrict === 2
  }

  private needMask(): boolean {
    return this.appSettings.antiSocialDeath && this.isR18() && !this.revealedR18
  }

  openViewer(pageIndex: number) {
    let settings = userSettingStore.getSettings()
    let urls = buildPageUrls(this.illust, settings.fullScreenQuality)
    let downloadUrls = buildPageUrls(this.illust, settings.downloadQuality)
    router.pushUrl({
      url: 'pages/detail/ImageViewerPage',
      params: { urls: urls, downloadUrls: downloadUrls, illust: this.illust, pageIndex: pageIndex }
    })
  }

  @Builder
  BookmarkMenuBuilder() {
    Column() {
      Text('公开收藏')
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => { this.store.starWithRestrict('public') })
      Text('私密收藏')
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => { this.store.starWithRestrict('private') })
    }
    .width(140)
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  SaveMenuBuilder() {
    Column() {
      Text('保存当前页')
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => { this.store.savePage(this.saveMenuPageIndex) })
      if (this.illust.pageCount > 1) {
        Text('保存全部页')
          .fontSize(14)
          .fontColor('#333333')
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .onClick(() => { this.store.saveAll() })
      }
    }
    .width(140)
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  TagMenuBuilder() {
    Column() {
      Text('屏蔽该标签')
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => {
          userSettingStore.addMuteTag(this.tagMenuTarget)
        })
      Text('复制标签名')
        .fontSize(14)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => {
          let data = pasteboard.createPlainTextData(this.tagMenuTarget)
          pasteboard.getSystemPasteboard().setData(data)
        })
    }
    .width(140)
    .padding({ top: 4, bottom: 4 })
  }

  goToUserProfile() {
    if (this.illust.user.id > 0) {
      router.pushUrl({ url: 'pages/user/UserProfilePage', params: { userId: this.illust.user.id } })
    }
  }

  @Builder
  TagChip(tag: Tag) {
    if (userSettingStore.getSettings().showTranslatedTags && tag.translatedName) {
      Column() {
        Text(tag.name)
          .fontSize(10)
          .fontColor('#0096FA')
        Text(tag.translatedName)
          .fontSize(8)
          .fontColor('#0096FA')
          .opacity(0.8)
      }
      .backgroundColor('#E6F4FF')
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .borderRadius(12)
      .margin({ right: 4, bottom: 4 })
      .onClick(() => {
        router.pushUrl({ url: 'pages/search/TagSearchPage', params: { keyword: tag.name } })
      })
      .gesture(
        LongPressGesture({ duration: 500 })
          .onAction(() => {
            this.tagMenuTarget = tag.name
            this.tagMenuShown = true
          })
      )
      .bindContextMenu(this.tagMenuShown && this.tagMenuTarget === tag.name, this.TagMenuBuilder, {
        onDisappear: () => { this.tagMenuShown = false }
      })
    } else {
      Text(tag.name)
        .fontSize(10)
        .fontColor('#0096FA')
        .backgroundColor('#E6F4FF')
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(12)
        .margin({ right: 4, bottom: 4 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/search/TagSearchPage', params: { keyword: tag.name } })
        })
        .gesture(
          LongPressGesture({ duration: 500 })
            .onAction(() => {
              this.tagMenuTarget = tag.name
              this.tagMenuShown = true
            })
        )
        .bindContextMenu(this.tagMenuShown && this.tagMenuTarget === tag.name, this.TagMenuBuilder, {
          onDisappear: () => { this.tagMenuShown = false }
        })
    }
  }

  @Builder
  ImageRow(row: DetailRow) {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (this.needMask()) {
        Column() {
          Text('🔒')
            .fontSize(28)
            .opacity(0.4)
          Text('点击显示')
            .fontSize(12)
            .fontColor('rgba(255, 255, 255, 0.35)')
            .margin({ top: 8 })
        }
        .width('100%')
        .aspectRatio(row.ratio)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#E0E0E0')
        .borderRadius(8)
        .onClick(() => { this.revealedR18 = true })
      } else {
        CachedImage({ url: row.imageUrl, ratio: row.ratio, fit: ImageFit.Contain })
      }
      if (this.illust.pageCount > 1 && !this.needMask()) {
        Text((row.pageIndex + 1) + '/' + this.illust.pageCount)
          .fontSize(10)
          .fontColor('#FFFFFF')
          .backgroundColor('rgba(0, 0, 0, 0.6)')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(8)
          .margin(6)
      }
    }
    .width('100%')
    .onClick(() => {
      if (this.needMask()) {
        this.revealedR18 = true
        return
      }
      this.openViewer(row.pageIndex)
    })
    .gesture(
      LongPressGesture({ duration: 500 })
        .onAction(() => {
          if (!this.needMask()) {
            if (this.illust.pageCount > 1) {
              this.saveMenuPageIndex = row.pageIndex
              this.saveMenuShown = true
            } else {
              this.store.savePage(row.pageIndex)
            }
          }
        })
    )
    .bindContextMenu(this.saveMenuShown && this.saveMenuPageIndex === row.pageIndex, this.SaveMenuBuilder, {
      onDisappear: () => { this.saveMenuShown = false }
    })
  }

  @Builder
  InfoRow() {
    Column() {
      Row() {
        Text(this.illust.title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })

      Row() {
        if (this.userAvatarPath) {
          Image('file://' + this.userAvatarPath)
            .width(32)
            .height(32)
            .borderRadius(16)
        } else {
          Column()
            .width(32)
            .height(32)
            .borderRadius(16)
            .backgroundColor('#F5F5F5')
        }
        Text(this.illust.user.name)
          .fontSize(14)
          .fontColor('#0096FA')
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })
      .onClick(() => { this.goToUserProfile() })

      Row() {
        Text('收藏 ' + this.illust.totalBookmarks)
          .fontSize(12)
          .fontColor('#999999')
        Text('浏览 ' + this.illust.totalView)
          .fontSize(12)
          .fontColor('#999999')
          .margin({ left: 16 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.illust.tags, (tag: Tag) => {
          this.TagChip(tag)
        }, (tag: Tag) => tag.name)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })

      Row() {
        Button(this.bookmarkState() === BOOKMARK_LOADING ? '收藏中...' :
          this.bookmarkState() === BOOKMARK_DONE ? '已收藏' : '收藏')
          .width('28%')
          .fontSize(13)
          .backgroundColor(this.bookmarkState() === BOOKMARK_DONE ? '#FF6B6B' :
            this.bookmarkState() === BOOKMARK_LOADING ? '#999999' : '#0096FA')
          .enabled(this.bookmarkState() !== BOOKMARK_LOADING)
          .onClick(() => { this.store.toggleBookmark() })
          .gesture(
            LongPressGesture({ duration: 500 })
              .onAction(() => {
                if (this.bookmarkState() === 0) {
                  this.bookmarkMenuShown = true
                }
              })
          )
          .bindContextMenu(this.bookmarkMenuShown, this.BookmarkMenuBuilder, {
            onDisappear: () => { this.bookmarkMenuShown = false }
          })

        Button('保存图片')
          .width('28%')
          .fontSize(13)
          .backgroundColor('#0096FA')
          .onClick(() => {
            if (this.illust.pageCount > 1) {
              this.saveMenuPageIndex = 0
              this.saveMenuShown = true
            } else {
              this.store.savePage(0)
            }
          })
          .bindContextMenu(this.saveMenuShown && this.saveMenuPageIndex === 0, this.SaveMenuBuilder, {
            onDisappear: () => { this.saveMenuShown = false }
          })

        if (this.illust.pageCount > 1) {
          Button('下载全部')
            .width('28%')
            .fontSize(13)
            .backgroundColor('#FF8800')
            .onClick(() => { this.store.saveAll() })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .padding({ top: 16, bottom: 16 })
    }
    .width('100%')
  }

  @Builder
  RelatedHeaderRow() {
    Row() {
      Text('相关作品')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  @Builder
  RelatedRow(row: DetailRow) {
    Row() {
      ForEach(row.related, (item: Illust) => {
        Column() {
          IllustCard({
            illust: item,
            onCardClick: (target: Illust) => {
              router.pushUrl({ url: 'pages/detail/IllustDetailPage', params: { illustId: target.id } })
            }
          })
        }
        .width('33.3%')
      }, (item: Illust) => item.id.toString())
    }
    .width('100%')
  }

  build() {
    Column() {
      if (this.errorMessage && this.rows.length === 0) {
        ErrorView({ message: this.errorMessage, onRetry: () => { this.loadDetail(this.illustId) } })
      } else if (this.isLoading && this.rows.length === 0) {
        LoadingView()
      } else {
        List() {
          ForEach(this.rows, (row: DetailRow) => {
            ListItem() {
              if (row.kind === 'image') {
                this.ImageRow(row)
              } else if (row.kind === 'info') {
                this.InfoRow()
              } else if (row.kind === 'related_header') {
                this.RelatedHeaderRow()
              } else {
                this.RelatedRow(row)
              }
            }
          }, (row: DetailRow) => row.kind + '_' + row.pageIndex + '_' +
            (row.related.length > 0 ? row.related[0].id : 0))
        }
        .width('100%')
        .layoutWeight(1)
        .onReachEnd(() => {
          this.store.loadMoreRelated().then(() => {
            this.rebuildRows()
          }).catch((e: Object) => {
            console.error('Load more related failed: ' + e)
          })
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
