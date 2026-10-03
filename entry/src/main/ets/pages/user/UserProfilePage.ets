import { router } from '@kit.ArkUI';
import { apiService } from '../../network/ApiService';
import { User, ProfileStats, profileStatsFromJson } from '../../models/User';
import { imageCacheService } from '../../services/ImageCacheService';
import { ErrorView } from '../../components/common/CommonViews';
import { FollowButton } from '../../components/common/FollowButton';
import { IllustWaterfall, IllustListPage, parseIllustListPage } from '../../components/illust/IllustWaterfall';
import { continuationService } from '../../services/ContinuationService';
import { ContinuationPayload, CONTINUATION_PAGE_USER_PROFILE } from '../../models/ContinuationPayload';
import { getStr, getStrf } from '../../utils/I18nUtils';

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
  /** 关注态（三态 FollowButton 由 @State 驱动，避免直接改 user 对象属性不刷新） */
  @State isFollowed: boolean = false

  aboutToAppear() {
    let params = router.getParams() as UserRouteParams
    if (params && params.userId) {
      this.userId = params.userId
      this.loadProfile(params.userId)
      // 多端流转：登记当前页面状态（用户主页 = userId）
      continuationService.setCurrentPageState(new ContinuationPayload({
        page: CONTINUATION_PAGE_USER_PROFILE,
        userId: params.userId
      }))
    }
  }

  aboutToDisappear() {
    // 多端流转：清除页面状态登记
    continuationService.setCurrentPageState(null)
  }

  async loadProfile(id: number) {
    this.isLoading = true
    this.profileError = ''
    try {
      let response = await apiService.getUserDetail(id)
      let detail = response as UserDetailResponse
      if (detail.user) {
        this.user = User.fromJson(detail.user)
        this.isFollowed = this.user.isFollowed
        this.loadAvatar()
      }
      // 统计字段位于响应的 profile 对象内（user 对象不含这些字段）
      if (detail.profile) {
        this.stats = profileStatsFromJson(detail.profile)
      }
    } catch (e) {
      this.profileError = getStrf($r('app.string.common_load_failed_detail'), String(e))
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
            Text(getStrf($r('app.string.user_stat_follow'), this.stats.totalFollowUsers))
              .fontSize(12)
              .fontColor('#999999')
            Text(getStrf($r('app.string.user_stat_works'), this.stats.totalIllusts))
              .fontSize(12)
              .fontColor('#999999')
              .margin({ left: 16 })
          }
          .margin({ top: 8 })
          // 三态关注按钮（实心/描边/请求中小菊花；单击快关，长按精细关注菜单）
          FollowButton({
            userId: this.user.id,
            isFollowed: this.isFollowed,
            onChanged: (newState: boolean) => { this.isFollowed = newState }
          })
            .margin({ top: 12 })
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
