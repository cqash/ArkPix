import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { picker, fileIo } from '@kit.CoreFileKit';
import { userSettingStore } from '../../stores/UserSettingStore';
import { AppSettings, ExifTagMergeRule } from '../../models/AppSettings';

interface ExifExportData {
  version: number
  appName: string
  exifMutedTags: string[]
  exifMergedTags: ExifTagMergeRuleData[]
  exifTagPriority: string[]
}

interface ExifTagMergeRuleData {
  mainTag: string
  fromTags: string[]
}

@Entry
@Component
struct ExifTagConfigPage {
  @State settings: AppSettings = userSettingStore.getSettings()
  @State newMutedTag: string = ''
  @State newMergeMainTag: string = ''
  @State newMergeFromTags: string = ''
  @State newPriorityTag: string = ''

  private refresh(): void {
    this.settings = userSettingStore.getSettings()
  }

  // ====== Muted Tags ======
  private addMutedTag(): void {
    let tag = this.newMutedTag.trim()
    if (!tag) {
      return
    }
    userSettingStore.addExifMutedTag(tag)
    this.newMutedTag = ''
    this.refresh()
  }

  private removeMutedTag(tag: string): void {
    userSettingStore.removeExifMutedTag(tag)
    this.refresh()
  }

  // ====== Merge Rules ======
  private addMergeRule(): void {
    let mainTag = this.newMergeMainTag.trim()
    let fromStr = this.newMergeFromTags.trim()
    if (!mainTag || !fromStr) {
      return
    }
    let fromTags: string[] = []
    let parts = fromStr.split(',')
    for (let i = 0; i < parts.length; i++) {
      let part = parts[i].trim()
      if (part.length > 0) {
        fromTags.push(part)
      }
    }
    if (fromTags.length === 0) {
      return
    }
    userSettingStore.addExifMergeRule(mainTag, fromTags)
    this.newMergeMainTag = ''
    this.newMergeFromTags = ''
    this.refresh()
  }

  private removeMergeRule(mainTag: string): void {
    userSettingStore.removeExifMergeRule(mainTag)
    this.refresh()
  }

  // ====== Priority ======
  private addPriorityTag(): void {
    let tag = this.newPriorityTag.trim()
    if (!tag) {
      return
    }
    let current = this.settings.exifTagPriority.slice()
    if (!current.includes(tag)) {
      current.push(tag)
      userSettingStore.setExifTagPriority(current)
    }
    this.newPriorityTag = ''
    this.refresh()
  }

  private removePriorityTag(tag: string): void {
    let current = this.settings.exifTagPriority.slice()
    let index = current.indexOf(tag)
    if (index >= 0) {
      current.splice(index, 1)
      userSettingStore.setExifTagPriority(current)
    }
    this.refresh()
  }

  // ====== Import / Export ======
  private async exportData(): Promise<void> {
    let exportData: ExifExportData = {
      version: 1,
      appName: 'ArkPix',
      exifMutedTags: this.settings.exifMutedTags.slice(),
      exifMergedTags: this.settings.exifMergedTags.map(
        (rule: ExifTagMergeRule): ExifTagMergeRuleData => {
          return { mainTag: rule.mainTag, fromTags: rule.fromTags.slice() }
        }
      ),
      exifTagPriority: this.settings.exifTagPriority.slice()
    }
    let json = JSON.stringify(exportData)

    try {
      let ctx = AppStorage.get<common.Context>('context')
      if (!ctx) {
        promptAction.showToast({ message: '导出失败：无法获取上下文' })
        return
      }
      let options = new picker.DocumentSaveOptions()
      options.newFileNames = ['arkpix-exif-tags.json']
      let docPicker = new picker.DocumentViewPicker(ctx)
      let uris: Array<string> = await docPicker.save(options)
      if (uris.length === 0) {
        return
      }
      let file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
      fileIo.writeSync(file.fd, json)
      fileIo.closeSync(file)
      promptAction.showToast({ message: '导出成功' })
    } catch (e) {
      promptAction.showToast({ message: '导出失败: ' + e })
    }
  }

  private async importData(): Promise<void> {
    try {
      let ctx = AppStorage.get<common.Context>('context')
      if (!ctx) {
        promptAction.showToast({ message: '导入失败：无法获取上下文' })
        return
      }
      let selectOptions = new picker.DocumentSelectOptions()
      selectOptions.maxSelectNumber = 1
      selectOptions.fileSuffixFilters = ['JSON|.json']
      let docPicker = new picker.DocumentViewPicker(ctx)
      let uris: Array<string> = await docPicker.select(selectOptions)
      if (uris.length === 0) {
        return
      }
      let content: string = fileIo.readTextSync(uris[0])
      let parsed: ExifExportData = JSON.parse(content) as ExifExportData

      // Validate version
      if (parsed.version !== 1) {
        promptAction.showToast({ message: '不支持该格式版本' })
        return
      }
      if (!parsed.exifMutedTags || !parsed.exifMergedTags || !parsed.exifTagPriority) {
        promptAction.showToast({ message: '文件格式不正确' })
        return
      }

      // Merge exifMutedTags: deduplicate
      let currentMuted = this.settings.exifMutedTags.slice()
      for (let i = 0; i < parsed.exifMutedTags.length; i++) {
        if (!currentMuted.includes(parsed.exifMutedTags[i])) {
          currentMuted.push(parsed.exifMutedTags[i])
        }
      }
      userSettingStore.setExifMutedTags(currentMuted)

      // Merge exifMergedTags: by mainTag, deduplicate fromTags
      for (let r = 0; r < parsed.exifMergedTags.length; r++) {
        let rule = parsed.exifMergedTags[r]
        if (!rule.mainTag || !rule.fromTags) {
          continue
        }
        userSettingStore.addExifMergeRule(rule.mainTag, rule.fromTags)
      }

      // Merge exifTagPriority: append new tags at end
      let currentPriority = this.settings.exifTagPriority.slice()
      for (let i = 0; i < parsed.exifTagPriority.length; i++) {
        if (!currentPriority.includes(parsed.exifTagPriority[i])) {
          currentPriority.push(parsed.exifTagPriority[i])
        }
      }
      userSettingStore.setExifTagPriority(currentPriority)

      this.refresh()
      promptAction.showToast({ message: '导入成功' })
    } catch (e) {
      promptAction.showToast({ message: '导入失败: ' + e })
    }
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Text('< 返回')
          .fontSize(16)
          .fontColor('#0096FA')
          .onClick(() => {
            router.back()
          })
        Text('EXIF 标签管理')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('    ')
          .fontSize(16)
          .width(48)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor('#FFFFFF')

      List() {
        // ====== 备注屏蔽标签 ======
        ListItem() {
          Column() {
            Text('备注屏蔽标签')
              .fontSize(12)
              .fontColor('#999999')
              .width('100%')
              .padding({ left: 16, bottom: 4 })

            Row() {
              TextInput({ placeholder: '输入要屏蔽的标签名', text: $$this.newMutedTag })
                .height(40)
                .layoutWeight(1)
                .backgroundColor('#FFFFFF')
                .onSubmit(() => { this.addMutedTag() })
              Button('添加')
                .height(40)
                .backgroundColor('#0096FA')
                .margin({ left: 8 })
                .onClick(() => { this.addMutedTag() })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor('#FFFFFF')

            if (this.settings.exifMutedTags.length === 0) {
              Text('暂无屏蔽标签（可在详情页标签长按菜单中添加）')
                .fontSize(13)
                .fontColor('#CCCCCC')
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 16, bottom: 16 })
            }

            ForEach(this.settings.exifMutedTags, (tag: string) => {
              Row() {
                Text(tag)
                  .fontSize(14)
                  .fontColor('#333333')
                  .layoutWeight(1)
                Text('删除')
                  .fontSize(12)
                  .fontColor('#FF4444')
                  .onClick(() => { this.removeMutedTag(tag) })
              }
              .width('100%')
              .height(44)
              .padding({ left: 16, right: 16 })
              .backgroundColor('#FFFFFF')
            }, (tag: string) => tag)
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
        }

        // ====== 备注合并规则 ======
        ListItem() {
          Column() {
            Text('备注合并规则')
              .fontSize(12)
              .fontColor('#999999')
              .width('100%')
              .padding({ left: 16, bottom: 4 })

            Text('下载时，从属标签将被主标签替代，节省备注空间')
              .fontSize(11)
              .fontColor('#AAAAAA')
              .width('100%')
              .padding({ left: 16, bottom: 8 })

            Column() {
              Row() {
                Text('主标签：')
                  .fontSize(12)
                  .fontColor('#666666')
                  .width(60)
                TextInput({ placeholder: '如: 女孩子', text: $$this.newMergeMainTag })
                  .height(36)
                  .layoutWeight(1)
                  .backgroundColor('#F5F5F5')
              }
              .width('100%')
              .margin({ bottom: 6 })

              Row() {
                Text('从属：')
                  .fontSize(12)
                  .fontColor('#666666')
                  .width(60)
                TextInput({ placeholder: '逗号分隔，如: 女の子,girl', text: $$this.newMergeFromTags })
                  .height(36)
                  .layoutWeight(1)
                  .backgroundColor('#F5F5F5')
              }
              .width('100%')
              .margin({ bottom: 8 })

              Button('添加合并规则')
                .height(36)
                .backgroundColor('#0096FA')
                .fontColor('#FFFFFF')
                .fontSize(13)
                .width('100%')
                .onClick(() => { this.addMergeRule() })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor('#FFFFFF')

            if (this.settings.exifMergedTags.length === 0) {
              Text('暂无合并规则（可在详情页标签长按菜单中添加）')
                .fontSize(13)
                .fontColor('#CCCCCC')
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 16, bottom: 16 })
                .backgroundColor('#FFFFFF')
            }

            ForEach(this.settings.exifMergedTags, (rule: ExifTagMergeRule) => {
              Row() {
                Column() {
                  Text(rule.mainTag)
                    .fontSize(14)
                    .fontColor('#0096FA')
                    .fontWeight(FontWeight.Medium)
                  Text('← ' + rule.fromTags.join(', '))
                    .fontSize(12)
                    .fontColor('#666666')
                    .margin({ top: 2 })
                }
                .layoutWeight(1)
                Text('删除')
                  .fontSize(12)
                  .fontColor('#FF4444')
                  .onClick(() => { this.removeMergeRule(rule.mainTag) })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .backgroundColor('#FFFFFF')
            }, (rule: ExifTagMergeRule) => rule.mainTag)
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
        }

        // ====== 优先级排序 ======
        ListItem() {
          Column() {
            Text('优先级排序')
              .fontSize(12)
              .fontColor('#999999')
              .width('100%')
              .padding({ left: 16, bottom: 4 })

            Text('下载时标签按此优先级排序写入备注，索引越小越优先')
              .fontSize(11)
              .fontColor('#AAAAAA')
              .width('100%')
              .padding({ left: 16, bottom: 8 })

            Row() {
              TextInput({ placeholder: '输入标签名', text: $$this.newPriorityTag })
                .height(40)
                .layoutWeight(1)
                .backgroundColor('#FFFFFF')
                .onSubmit(() => { this.addPriorityTag() })
              Button('添加')
                .height(40)
                .backgroundColor('#0096FA')
                .margin({ left: 8 })
                .onClick(() => { this.addPriorityTag() })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor('#FFFFFF')

            if (this.settings.exifTagPriority.length === 0) {
              Text('暂无优先级规则（优先级为空时标签按原始顺序排列）')
                .fontSize(13)
                .fontColor('#CCCCCC')
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 16, bottom: 16 })
                .backgroundColor('#FFFFFF')
            }

            ForEach(this.settings.exifTagPriority, (tag: string, index: number) => {
              Row() {
                Text((index + 1) + '.')
                  .fontSize(14)
                  .fontColor('#999999')
                  .width(30)
                Text(tag)
                  .fontSize(14)
                  .fontColor('#333333')
                  .layoutWeight(1)
                Text('删除')
                  .fontSize(12)
                  .fontColor('#FF4444')
                  .onClick(() => { this.removePriorityTag(tag) })
              }
              .width('100%')
              .height(44)
              .padding({ left: 16, right: 16 })
              .backgroundColor('#FFFFFF')
            }, (tag: string, index: number) => tag + '_' + index)
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
        }

        // ====== 导入导出 ======
        ListItem() {
          Column() {
            Text('导入导出')
              .fontSize(12)
              .fontColor('#999999')
              .width('100%')
              .padding({ left: 16, bottom: 4 })

            Text('将规则导出为 JSON 文件，或从 JSON 文件导入（导入时与现有规则合并去重）')
              .fontSize(11)
              .fontColor('#AAAAAA')
              .width('100%')
              .padding({ left: 16, bottom: 8 })

            Row({ space: 12 }) {
              Button('导出')
                .fontSize(14)
                .backgroundColor('#0096FA')
                .fontColor('#FFFFFF')
                .layoutWeight(1)
                .onClick(() => { this.exportData() })
              Button('导入')
                .fontSize(14)
                .backgroundColor('#FF8800')
                .fontColor('#FFFFFF')
                .layoutWeight(1)
                .onClick(() => { this.importData() })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 16 })
            .backgroundColor('#FFFFFF')
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
        }
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
