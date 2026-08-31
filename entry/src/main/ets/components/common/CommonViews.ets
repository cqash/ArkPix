import { getStr } from '../../utils/I18nUtils';

@Component
export struct LoadingView {
  build() {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color('#0096FA')
      Text($r('app.string.common_loading'))
        .fontSize(14)
        .fontColor('#999999')
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}

@Component
export struct ErrorView {
  message: string = getStr($r('app.string.common_load_failed'))
  onRetry: () => void = () => {}

  build() {
    Column() {
      Text(this.message)
        .fontSize(16)
        .fontColor('#999999')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .padding({ left: 16, right: 16 })
      Button($r('app.string.common_retry'))
        .width(120)
        .height(36)
        .backgroundColor('#0096FA')
        .margin({ top: 12 })
        .onClick(this.onRetry)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}

@Component
export struct EmptyView {
  message: string = getStr($r('app.string.common_empty'))

  build() {
    Column() {
      Text(this.message)
        .fontSize(14)
        .fontColor('#999999')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
