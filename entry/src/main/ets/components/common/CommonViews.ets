@Component
export struct LoadingView {
  build() {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color('#0096FA')
      Text('加载中...')
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
  message: string = '加载失败'
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
      Button('重试')
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
  message: string = '暂无内容'

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
