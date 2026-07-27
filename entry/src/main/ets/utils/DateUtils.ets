/**
 * 发布日期格式化（纯函数，便于单测）。
 * 输入 Pixiv 的 ISO 8601 字符串（如 2024-05-18T14:32:00+09:00），
 * 用 new Date 解析后按设备本地时区输出 yyyy-MM-dd HH:mm；解析失败返回 ''（UI 不渲染该行）。
 */
export function formatCreateDate(iso: string): string {
  if (iso.length === 0) {
    return ''
  }
  let date = new Date(iso)
  if (isNaN(date.getTime())) {
    return ''
  }
  let year = date.getFullYear().toString()
  let month = padTwo(date.getMonth() + 1)
  let day = padTwo(date.getDate())
  let hour = padTwo(date.getHours())
  let minute = padTwo(date.getMinutes())
  return `${year}-${month}-${day} ${hour}:${minute}`
}

function padTwo(value: number): string {
  return value.toString().padStart(2, '0')
}
