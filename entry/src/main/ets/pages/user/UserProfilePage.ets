import { router } from '@kit.ArkUI';
import { apiService } from '../../network/ApiService';
import { Illust } from '../../models/Illust';
import { User } from '../../models/User';
import { imageCacheService } from '../../services/ImageCacheService';
import { CachedImage } from '../../components/common/CachedImage';

interface UserRouteParams {
  userId: number
}

interface UserDetailResponse {
  user: Object
}

interface UserIllustsResponse {
  illusts: Object[]
}

@Component
export struct UserProfilePage {
  @State user: User = new User()
  @State works: Illust[] = []
  @State isLoading: boolean = false
  @State avatarPath: string = ''

  aboutToAppear() {
    let params = router.getParams() as UserRouteParams
    if (params && params.userId) {
      this.loadProfile(params.userId)
      this.loadWorks(params.userId)
    }
  }

  async loadProfile(id: number) {
    this.isLoading = true
    try {
      let response = await apiService.getUserDetail(id)
      let user = (response as UserDetailResponse).user
      if (user) {
        this.user = User.fromJson(user)
        this.loadAvatar()
      }
    } catch (e) {
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

  async loadWorks(id: number) {
    try {
      let response = await apiService.getUserIllusts(id)
      let illusts = (response as UserIllustsResponse).illusts
      if (illusts) {
        this.works = illusts.map((item: Object) => Illust.fromJson(item))
      }
    } catch (e) {
      console.error('Load works failed: ' + e)
    }
  }

  async toggleFollow() {
    try {
      if (this.user.isFollowed) {
        await apiService.unfollowUser(this.user.id)
      } else {
        await apiService.followUser(this.user.id, 'public')
      }
      this.user.isFollowed = !this.user.isFollowed
    } catch (e) {
      console.error('Follow failed: ' + e)
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
            Text('关注 ' + this.user.totalFollowUsers)
              .fontSize(12)
              .fontColor('#999999')
            Text('作品 ' + this.user.totalIllusts)
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

        List({ space: 8 }) {
          ForEach(this.works, (item: Illust) => {
            ListItem() {
              Column() {
                CachedImage({ url: item.imageUrls.medium })
              }
              .width('100%')
              .padding(4)
              .onClick(() => {
                router.pushUrl({ url: 'pages/detail/IllustDetailPage', params: { illustId: item.id } })
              })
            }
          }, (item: Illust) => item.id.toString())
        }
        .lanes(2)
        .padding(8)
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
  }
}
