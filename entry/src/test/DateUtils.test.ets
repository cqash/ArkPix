import { describe, it, expect } from '@ohos/hypium';
import { formatCreateDate } from '../main/ets/utils/DateUtils';

export default function dateUtilsTest() {
  describe('DateUtilsTest', () => {
    it('should_format_iso_with_timezone_to_local_yyyyMMddHHmm', 0, () => {
      let iso = '2024-05-18T14:32:00+09:00'
      let result = formatCreateDate(iso)
      // 本地时区输出，格式 yyyy-MM-dd HH:mm
      let pattern = new RegExp('^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}$')
      expect(pattern.test(result)).assertTrue()
      // 与 new Date 本地时区语义一致（+09:00 输入换算到设备本地时区）
      let date = new Date(iso)
      let expected = date.getFullYear().toString() + '-' +
        (date.getMonth() + 1).toString().padStart(2, '0') + '-' +
        date.getDate().toString().padStart(2, '0') + ' ' +
        date.getHours().toString().padStart(2, '0') + ':' +
        date.getMinutes().toString().padStart(2, '0')
      expect(result).assertEqual(expected)
    })

    it('should_pad_single_digit_fields', 0, () => {
      let iso = '2024-01-05T03:04:00+00:00'
      let result = formatCreateDate(iso)
      expect(result.length).assertEqual(16)
      let pattern = new RegExp('^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}$')
      expect(pattern.test(result)).assertTrue()
    })

    it('should_return_empty_for_invalid_input', 0, () => {
      expect(formatCreateDate('')).assertEqual('')
      expect(formatCreateDate('not-a-date')).assertEqual('')
    })
  })
}
