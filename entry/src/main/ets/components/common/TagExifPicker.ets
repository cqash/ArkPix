import {
  ExifTag,
  ExifInfo,
  filterTagsForExif,
  renderCommentWithTags,
  renderCommentBytes,
  utf8ByteLength,
  EXIF_FIELD_MAX_BYTES
} from '../../services/ImageExifService'
import { AppSettings } from '../../models/AppSettings'
import { Constants } from '../../utils/Constants'

interface TagExifPickerItem {
  name: string
  translatedName: string
  checked: boolean
  isMerged: boolean
  mergedFrom: string[]
  withinBudget: boolean
}

@CustomDialog
@Component
struct TagExifPicker {
  // Inputs
  tags: ExifTag[] = []
  exifInfo: ExifInfo | null = null
  settings: AppSettings | null = null

  controller: CustomDialogController

  // Output callbacks
  onConfirm: (selectedTags: string[], allTagsOrdered: string[]) => void = (_selectedTags: string[], _allTagsOrdered: string[]) => {}
  onSkip: () => void = () => {}

  // Internal state
  @State writableItems: TagExifPickerItem[] = []
  @State mutedItems: TagExifPickerItem[] = []
  @State previewText: string = ''
  @State previewBytes: number = 0
  @State dragFromIndex: number = -1

  aboutToAppear(): void {
    if (this.settings === null || this.exifInfo === null) {
      return
    }
    let settings = this.settings

    // Step 1: Filter tags using the service function
    let filteredTags = filterTagsForExif(this.tags, settings)

    // Step 2: Build mergedFrom map from settings
    let mergedFromMap: Record<string, string[]> = {} as Record<string, string[]>
    for (let r = 0; r < settings.exifMergedTags.length; r++) {
      let rule = settings.exifMergedTags[r]
      let fromList: string[] = []
      for (let f = 0; f < rule.fromTags.length; f++) {
        fromList.push(rule.fromTags[f])
      }
      mergedFromMap['k_' + rule.mainTag] = fromList
    }

    // Step 3: Separate writable vs muted
    let writable: TagExifPickerItem[] = []
    let muted: TagExifPickerItem[] = []

    for (let i = 0; i < filteredTags.length; i++) {
      let tag = filteredTags[i]
      let isMuted = settings.exifMutedTags.includes(tag.name)
      let mergedFrom = mergedFromMap['k_' + tag.name]
      let item: TagExifPickerItem = {
        name: tag.name,
        translatedName: tag.translatedName,
        checked: true,
        isMerged: mergedFrom !== undefined && mergedFrom.length > 0,
        mergedFrom: mergedFrom !== undefined ? mergedFrom : [],
        withinBudget: true
      }
      if (isMuted) {
        item.checked = false
        muted.push(item)
      } else {
        writable.push(item)
      }
    }

    // Also add tags that are in exifMutedTags but not in filteredTags
    // (they were removed by filterTagsForExif but we still show them in muted section)
    let filteredNames: string[] = []
    for (let i = 0; i < filteredTags.length; i++) {
      filteredNames.push(filteredTags[i].name)
    }
    for (let i = 0; i < this.tags.length; i++) {
      let tag = this.tags[i]
      if (settings.exifMutedTags.includes(tag.name) && !filteredNames.includes(tag.name)) {
        let mergedFrom = mergedFromMap['k_' + tag.name]
        let item: TagExifPickerItem = {
          name: tag.name,
          translatedName: tag.translatedName,
          checked: false,
          isMerged: mergedFrom !== undefined && mergedFrom.length > 0,
          mergedFrom: mergedFrom !== undefined ? mergedFrom : [],
          withinBudget: false
        }
        let alreadyInMuted = false
        for (let m = 0; m < muted.length; m++) {
          if (muted[m].name === tag.name) {
            alreadyInMuted = true
            break
          }
        }
        if (!alreadyInMuted) {
          muted.push(item)
        }
      }
    }

    // Step 4: Sort writable by exifTagPriority
    if (settings.exifTagPriority.length > 0) {
      let prioritized: TagExifPickerItem[] = []
      let remaining: TagExifPickerItem[] = []
      for (let p = 0; p < settings.exifTagPriority.length; p++) {
        for (let i = 0; i < writable.length; i++) {
          if (writable[i].name === settings.exifTagPriority[p]) {
            prioritized.push(writable[i])
          }
        }
      }
      for (let i = 0; i < writable.length; i++) {
        if (!settings.exifTagPriority.includes(writable[i].name)) {
          remaining.push(writable[i])
        }
      }
      writable = []
      for (let i = 0; i < prioritized.length; i++) {
        writable.push(prioritized[i])
      }
      for (let i = 0; i < remaining.length; i++) {
        writable.push(remaining[i])
      }
    }

    this.writableItems = writable
    this.mutedItems = muted
    this.recalculatePreview()
  }

  private recalculatePreview(): void {
    if (this.exifInfo === null || this.settings === null) {
      return
    }
    let info = this.exifInfo

    // Collect checked writable tags in order
    let checkedTags: ExifTag[] = []
    for (let i = 0; i < this.writableItems.length; i++) {
      if (this.writableItems[i].checked) {
        let item: ExifTag = { name: this.writableItems[i].name, translatedName: this.writableItems[i].translatedName }
        checkedTags.push(item)
      }
    }

    // Render full preview
    let rendered = renderCommentWithTags(info, checkedTags)
    let totalBytes = utf8ByteLength(rendered)
    this.previewText = rendered
    this.previewBytes = totalBytes

    // Calculate withinBudget for each writable item
    // Incrementally add tags and check byte count
    let budgetTags: ExifTag[] = []
    for (let i = 0; i < this.writableItems.length; i++) {
      if (this.writableItems[i].checked) {
        let t: ExifTag = { name: this.writableItems[i].name, translatedName: this.writableItems[i].translatedName }
        budgetTags.push(t)
        let partialBytes = renderCommentBytes(info, budgetTags)
        this.writableItems[i].withinBudget = partialBytes <= EXIF_FIELD_MAX_BYTES
      } else {
        this.writableItems[i].withinBudget = false
      }
    }
  }

  private swapWritableItems(from: number, to: number): void {
    if (from === to || from < 0 || to < 0 || from >= this.writableItems.length || to >= this.writableItems.length) {
      return
    }
    let item = this.writableItems[from]
    let newItems: TagExifPickerItem[] = []
    for (let i = 0; i < this.writableItems.length; i++) {
      if (i === from) {
        continue
      }
      if (i === to) {
        if (from < to) {
          newItems.push(this.writableItems[i])
          newItems.push(item)
        } else {
          newItems.push(item)
          newItems.push(this.writableItems[i])
        }
      } else {
        newItems.push(this.writableItems[i])
      }
    }
    this.writableItems = newItems
    this.recalculatePreview()
  }

  @Builder
  WritableItemBuilder(item: TagExifPickerItem, index: number) {
    Row() {
      Checkbox()
        .select(item.checked)
        .onChange((checked: boolean) => {
          if (!checked) {
            // Move to muted items
            let newWritable: TagExifPickerItem[] = []
            let movedItem: TagExifPickerItem | null = null
            for (let i = 0; i < this.writableItems.length; i++) {
              if (i === index) {
                movedItem = this.writableItems[i]
              } else {
                newWritable.push(this.writableItems[i])
              }
            }
            if (movedItem !== null) {
              let mutedItem: TagExifPickerItem = {
                name: movedItem.name,
                translatedName: movedItem.translatedName,
                checked: false,
                isMerged: movedItem.isMerged,
                mergedFrom: movedItem.mergedFrom,
                withinBudget: false
              }
              this.mutedItems = [...this.mutedItems, mutedItem]
            }
            this.writableItems = newWritable
            this.recalculatePreview()
          }
        })
      Column() {
        Text(item.name)
          .fontSize(13)
          .fontColor('#333333')
        if (Constants.filterTranslatedName(item.name, item.translatedName).length > 0) {
          Text(Constants.filterTranslatedName(item.name, item.translatedName))
            .fontSize(11)
            .fontColor('#666666')
            .margin({ top: 2 })
        }
        if (item.isMerged && item.mergedFrom.length > 0) {
          Text('合并自: ' + item.mergedFrom.join(', '))
            .fontSize(10)
            .fontColor('#0096FA')
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .margin({ left: 8 })
      Text('≡')
        .fontSize(18)
        .fontColor('#999999')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(item.withinBudget && item.checked ? '#E6F4FF' : '#F0F0F0')
    .borderRadius(6)
    .margin({ bottom: 4 })
  }

  @Builder
  MutedItemBuilder(item: TagExifPickerItem, index: number) {
    Row() {
      Text(item.name)
        .fontSize(13)
        .fontColor('#CC3333')
        .layoutWeight(1)
      if (Constants.filterTranslatedName(item.name, item.translatedName).length > 0) {
        Text(Constants.filterTranslatedName(item.name, item.translatedName))
          .fontSize(11)
          .fontColor('#999999')
          .margin({ left: 4 })
      }
      Text('恢复')
        .fontSize(12)
        .fontColor('#0096FA')
        .margin({ left: 8 })
        .onClick(() => {
          // Move back to writable items
          let newMuted: TagExifPickerItem[] = []
          let restoredItem: TagExifPickerItem | null = null
          for (let i = 0; i < this.mutedItems.length; i++) {
            if (i === index) {
              restoredItem = this.mutedItems[i]
            } else {
              newMuted.push(this.mutedItems[i])
            }
          }
          if (restoredItem !== null) {
            let writableItem: TagExifPickerItem = {
              name: restoredItem.name,
              translatedName: restoredItem.translatedName,
              checked: true,
              isMerged: restoredItem.isMerged,
              mergedFrom: restoredItem.mergedFrom,
              withinBudget: false
            }
            this.writableItems = [...this.writableItems, writableItem]
          }
          this.mutedItems = newMuted
          this.recalculatePreview()
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor('#FFEAEA')
    .borderRadius(6)
    .margin({ bottom: 4 })
  }

  build() {
    Column() {
      // Title
      Text('EXIF 备注标签选择')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 12 })

      // Preview area
      Column() {
        Text('预览')
          .fontSize(12)
          .fontColor('#999999')
          .margin({ bottom: 4 })
        Text(this.previewText)
          .fontSize(12)
          .fontColor('#333333')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.previewBytes + ' / ' + EXIF_FIELD_MAX_BYTES + ' 字节')
          .fontSize(12)
          .fontColor(this.previewBytes > EXIF_FIELD_MAX_BYTES ? '#CC3333' : '#0096FA')
          .margin({ top: 4 })
      }
      .width('100%')
      .padding(8)
      .backgroundColor('#F8F8F8')
      .borderRadius(8)
      .margin({ bottom: 12 })

      // Writable tags section
      Text('可写入标签')
        .fontSize(14)
        .fontColor('#333333')
        .fontWeight(FontWeight.Medium)
        .margin({ bottom: 6 })

      List() {
        ForEach(this.writableItems, (item: TagExifPickerItem, index: number) => {
          ListItem() {
            this.WritableItemBuilder(item, index)
          }
        }, (item: TagExifPickerItem, index: number) => item.name + '_' + index)
      }
      .width('100%')
      .layoutWeight(1)
      .divider({ strokeWidth: 0 })

      // Muted tags section
      if (this.mutedItems.length > 0) {
        Text('已屏蔽标签')
          .fontSize(14)
          .fontColor('#CC3333')
          .fontWeight(FontWeight.Medium)
          .margin({ top: 8, bottom: 6 })

        List() {
          ForEach(this.mutedItems, (item: TagExifPickerItem, index: number) => {
            ListItem() {
              this.MutedItemBuilder(item, index)
            }
          }, (item: TagExifPickerItem, index: number) => 'muted_' + item.name + '_' + index)
        }
        .width('100%')
        .height(Math.min(this.mutedItems.length * 50, 150))
        .divider({ strokeWidth: 0 })
      }

      // Action buttons
      Row({ space: 12 }) {
        Button('跳过')
          .fontSize(14)
          .backgroundColor('#EEEEEE')
          .fontColor('#333333')
          .layoutWeight(1)
          .onClick(() => {
            this.controller.close()
            this.onSkip()
          })
        Button('确认')
          .fontSize(14)
          .backgroundColor('#0096FA')
          .fontColor('#FFFFFF')
          .layoutWeight(1)
          .onClick(() => {
            let selectedTags: string[] = []
            let allTagsOrdered: string[] = []
            for (let i = 0; i < this.writableItems.length; i++) {
              allTagsOrdered.push(this.writableItems[i].name)
              if (this.writableItems[i].checked) {
                selectedTags.push(this.writableItems[i].name)
              }
            }
            this.controller.close()
            this.onConfirm(selectedTags, allTagsOrdered)
          })
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .padding(16)
    .width('100%')
    .height('80%')
    .backgroundColor('#FFFFFF')
    .borderRadius({ topLeft: 16, topRight: 16 })
  }
}
