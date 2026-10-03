import { ugoiraService } from '../../services/UgoiraService';
import { CachedImage } from '../common/CachedImage';

/**
 * ugoira 动图播放组件：帧包经 UgoiraService 下载解压后 ImageAnimator 逐帧无限循环。
 * 封面图常渲染在底层作占位；帧加载失败时静默停留在封面，调用方零感知。
 */
@Component
export struct UgoiraPlayer {
  @Prop illustId: number = 0
  @Prop ratio: number = 1
  @Prop fit: ImageFit = ImageFit.Contain
  @Prop coverUrl: string = ''
  @State frameInfos: ImageFrameInfo[] = []

  aboutToAppear() {
    this.loadFrames()
  }

  async loadFrames() {
    try {
      let playback = await ugoiraService.getPlayback(this.illustId)
      if (!playback || playback.framePaths.length === 0) {
        return
      }
      let infos: ImageFrameInfo[] = []
      for (let i = 0; i < playback.framePaths.length; i++) {
        let info: ImageFrameInfo = {
          src: 'file://' + playback.framePaths[i],
          duration: Math.max(10, playback.delaysMs[i])
        }
        infos.push(info)
      }
      this.frameInfos = infos
    } catch (e) {
      console.error('UgoiraPlayer load failed: ' + e)
    }
  }

  build() {
    Stack() {
      CachedImage({ url: this.coverUrl, ratio: this.ratio, fit: this.fit })
      if (this.frameInfos.length > 0) {
        ImageAnimator()
          .images(this.frameInfos)
          .state(AnimationStatus.Running)
          .iterations(-1)
          .width('100%')
          .aspectRatio(this.ratio)
      }
    }
    .width('100%')
    .aspectRatio(this.ratio)
  }
}
