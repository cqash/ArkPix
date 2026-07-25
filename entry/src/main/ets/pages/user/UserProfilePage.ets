import { router, promptAction } from '@kit.ArkUI';
import { apiService } from '../../network/ApiService';
import { User, ProfileStats, profileStatsFromJson } from '../../models/User';
import { imageCacheService } from '../../services/ImageCacheService';
import { ErrorView } from '../../components/common/CommonViews';
import { IllustWaterfall, IllustListPage, parseIllustListPage } from '../../components/illust/IllustWaterfall';

interface UserRouteParams {
  userId: number
}

interface UserDetailResponse {
  user: Object
  profile: Object
}

@Entry
@Component
export struct UserProfilePage {
  @State user: User = new User()
  @State stats: ProfileStats = new ProfileStats()
  @State isLoading: boolean = false
  @State avatarPath: string = ''
  @State profileError: string = ''
  @State userId: number = 0

  aboutToAppear() {
    let params = router.getParams() as UserRouteParams
    if (params && params.userId) {
      this.userId = params.userId
      this.loadProfile(params.userId)
    }
  }

  async loadProfile(id: number) {
    this.isLoading = true
    this.profileError = ''
    try {
      let response = await apiService.getUserDetail(id)
      let detail = response as UserDetailResponse
      if (detail.user) {
        this.user = User.fromJson(detail.user)
        this.loadAvatar()
      }
      // 统计字段位于响应的 profile 对象内（user 对象不含这些字段）
      if (detail.profile) {
        this.stats = profileStatsFromJson(detail.profile)
      }
    } catch (e) {
      this.profileError = '加载失败: ' + e
      console.error('Load profile failed: ' + e)
    } finally {
      this.isLoading = false
    }
  }

  async loadAvatar() {
    let url = this.user.profileImageUrls.medium
    if (url) {
      this.avatarPath = await imageCacheService.getLocalPath(url)
    }
  }

  private async fetchFirst(): Promise<IllustListPage> {
    let response = await apiService.getUserIllusts(this.userId)
    return parseIllustListPage(response)
  }

  async toggleFollow() {
    let wasFollowed = this.user.isFollowed
    try {
      if (wasFollowed) {
        await apiService.unfollowUser(this.user.id)
      } else {
        await apiService.followUser(this.user.id, 'public')
      }
      this.user.isFollowed = !wasFollowed
      promptAction.showToast({ message: wasFollowed ? '已取消关注' : '已关注' })
    } catch (e) {
      console.error('Follow failed: ' + e)
      promptAction.showToast({ message: (wasFollowed ? '取消关注失败' : '关注失败') + '，请重试' })
    }
  }

  build() {
    Column() {
      if (this.profileError && this.user.id === 0) {
        ErrorView({ message: this.profileError, onRetry: () => { this.loadProfile(this.userId) } })
      } else if (this.isLoading) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color('#0096FA')
      } else {
        Column() {
          if (this.avatarPath) {
            Image('file://' + this.avatarPath)
              .width(80)
              .height(80)
              .borderRadius(40)
          } else {
            Column()
              .width(80)
              .height(80)
              .borderRadius(40)
              .backgroundColor('#F5F5F5')
          }
          Text(this.user.name)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .margin({ top: 12 })
          Text(this.user.comment)
            .fontSize(12)
            .fontColor('#999999')
            .margin({ top: 4 })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row() {
            Text('关注 ' + this.stats.totalFollowUsers)
              .fontSize(12)
              .fontColor('#999999')
            Text('作品 ' + this.stats.totalIllusts)
              .fontSize(12)
              .fontColor('#999999')
              .margin({ left: 16 })
          }
          .margin({ top: 8 })
          Button(this.user.isFollowed ? '已关注' : '关注')
            .width(120)
            .height(36)
            .backgroundColor(this.user.isFollowed ? '#FF6B6B' : '#0096FA')
            .margin({ top: 12 })
            .onClick(() => { this.toggleFollow() })
        }
        .width('100%')
        .padding(16)
        .alignItems(HorizontalAlign.Center)

        // 作品列表接入公共瀑布流（分页/角标/红心/长按菜单自动获得）
        IllustWaterfall({
          fetchFirst: (): Promise<IllustListPage> => this.fetchFirst()
        })
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
  }
}
