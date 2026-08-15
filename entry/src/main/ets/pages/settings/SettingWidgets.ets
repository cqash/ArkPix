/**
 * 设置族页面共享组件与帮助函数。
 * 从 SettingsPage 原样抽取（组件实现与选项数组逐项一致），供 7 个分类子页与设置首页复用。
 */

@Component
export struct SettingItem {
  @Prop title: string = ''
  @Prop value: string = ''
  onItemClick: (() => void) | null = null

  build() {
    Row() {
      Text(this.title)
        .fontSize(14)
        .fontColor('#333333')
      Row() {
        Text(this.value)
          .fontSize(14)
          .fontColor('#0096FA')
        if (this.onItemClick) {
          Text(' >')
            .fontSize(16)
            .fontColor('#999999')
        }
      }
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.SpaceBetween)
    .padding({ left: 16, right: 16 })
    .backgroundColor('#FFFFFF')
    .stateStyles({
      pressed: {
        .backgroundColor('#F0F0F0')
      }
    })
    .onClick(() => {
      if (this.onItemClick) {
        this.onItemClick()
      }
    })
  }
}

@Component
export struct SwitchItem {
  @Prop title: string = ''
  @Prop isOn: boolean = false
  onToggle: (() => void) | null = null

  build() {
    Row() {
      Text(this.title)
        .fontSize(14)
        .fontColor('#333333')
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor('#0096FA')
        .onChange((isOn: boolean) => {
          if (this.onToggle) {
            this.onToggle()
          }
        })
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.SpaceBetween)
    .padding({ left: 16, right: 16 })
    .backgroundColor('#FFFFFF')
  }
}

@Component
export struct SectionHeader {
  @Prop title: string = ''

  build() {
    Text(this.title)
      .fontSize(12)
      .fontColor('#999999')
      .width('100%')
      .padding({ left: 16, bottom: 4 })
  }
}

@Component
export struct TextInputItem {
  @Prop title: string = ''
  @Prop placeholder: string = ''
  @Prop value: string = ''
  @State inputValue: string = ''
  isPassword: boolean = false
  onTextChange: ((text: string) => void) | null = null

  aboutToAppear() {
    this.inputValue = this.value
  }

  build() {
    Row() {
      Text(this.title)
        .fontSize(14)
        .fontColor('#333333')
      TextInput({ text: this.inputValue, placeholder: this.placeholder })
        .type(this.isPassword ? InputType.Password : InputType.Normal)
        .fontSize(14)
        .fontColor('#333333')
        .textAlign(TextAlign.End)
        .layoutWeight(1)
        .backgroundColor(Color.Transparent)
        .onChange((text: string) => {
          this.inputValue = text
          if (this.onTextChange) {
            this.onTextChange(text)
          }
        })
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.SpaceBetween)
    .padding({ left: 16, right: 16 })
    .backgroundColor('#FFFFFF')
  }
}

export interface QualityOption {
  label: string
  value: number
}

/** 多值选项：用 TextPickerDialog 选择，防止误触直接切换；仅值变化时回调 */
export function showQualityPicker(title: string, options: QualityOption[], currentValue: number,
  onSelect: (value: number) => void): void {
  let labels: string[] = []
  let selectedIndex: number = 0
  for (let i = 0; i < options.length; i++) {
    labels.push(options[i].label)
    if (options[i].value === currentValue) {
      selectedIndex = i
    }
  }
  TextPickerDialog.show({
    range: labels,
    selected: selectedIndex,
    onAccept: (result: TextPickerResult) => {
      let idx: number | number[] = result.index
      let index: number = 0
      if (typeof idx === 'number') {
        index = idx
      }
      if (index >= 0 && index < options.length && options[index].value !== currentValue) {
        onSelect(options[index].value)
      }
    }
  })
}

/** value→label 反查，供子页 value 列与首页摘要共用 */
export function labelOf(options: QualityOption[], value: number): string {
  for (let i = 0; i < options.length; i++) {
    if (options[i].value === value) {
      return options[i].label
    }
  }
  return ''
}

export const PREVIEW_QUALITY_OPTIONS: QualityOption[] = [
  { label: '缩略图', value: 0 },
  { label: '中图', value: 1 },
  { label: '大图', value: 2 }
]

export const DETAIL_QUALITY_OPTIONS: QualityOption[] = [
  { label: '大图', value: 0 },
  { label: '原图', value: 1 }
]

export const ILLUST_MANGA_QUALITY_OPTIONS: QualityOption[] = [
  { label: '中', value: 0 },
  { label: '大', value: 1 },
  { label: '原图', value: 2 }
]

export const NETWORK_MODE_OPTIONS: QualityOption[] = [
  { label: '标准', value: 0 },
  { label: '兼容', value: 1 },
  { label: '增强', value: 2 },
  { label: '中继', value: 3 }
]

export const NETWORK_MODE_VALUES: string[] = ['standard', 'compatible', 'ech', 'relay']

export const IMAGE_HOST_OPTIONS: QualityOption[] = [
  { label: '默认 (i.pximg.net)', value: 0 },
  { label: '可选 (i.pixiv.re)', value: 1 },
  { label: '自定义', value: 2 }
]

export const IMAGE_HOST_VALUES: string[] = ['default', 'optional', 'custom']

export const PROXY_TYPE_OPTIONS: QualityOption[] = [
  { label: 'HTTP', value: 0 },
  { label: 'SOCKS5', value: 1 }
]

export const DOWNLOAD_CONCURRENCY_OPTIONS: QualityOption[] = [
  { label: '1 线程', value: 1 },
  { label: '2 线程', value: 2 },
  { label: '3 线程', value: 3 },
  { label: '4 线程', value: 4 },
  { label: '5 线程', value: 5 }
]

export const CROSS_COUNT_OPTIONS: QualityOption[] = [
  { label: '2 列', value: 2 },
  { label: '3 列', value: 3 }
]

/** 网络模式字符串 → label（如 'standard' → '标准'），用于子页 value 列与首页摘要 */
export function networkModeLabel(mode: string): string {
  for (let i = 0; i < NETWORK_MODE_VALUES.length; i++) {
    if (NETWORK_MODE_VALUES[i] === mode) {
      return NETWORK_MODE_OPTIONS[i].label
    }
  }
  return ''
}

/** 网络模式字符串 → 选项索引（Picker 当前选中用） */
export function networkModeIndex(mode: string): number {
  for (let i = 0; i < NETWORK_MODE_VALUES.length; i++) {
    if (NETWORK_MODE_VALUES[i] === mode) {
      return i
    }
  }
  return 0
}

/** 图床类型字符串 → label */
export function imageHostLabel(hostType: string): string {
  for (let i = 0; i < IMAGE_HOST_VALUES.length; i++) {
    if (IMAGE_HOST_VALUES[i] === hostType) {
      return IMAGE_HOST_OPTIONS[i].label
    }
  }
  return ''
}

/** 图床类型字符串 → 选项索引（Picker 当前选中用） */
export function imageHostIndex(hostType: string): number {
  for (let i = 0; i < IMAGE_HOST_VALUES.length; i++) {
    if (IMAGE_HOST_VALUES[i] === hostType) {
      return i
    }
  }
  return 0
}
