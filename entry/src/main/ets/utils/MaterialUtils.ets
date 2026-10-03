import { deviceInfo } from '@kit.BasicServicesKit';
import lazy { uiMaterial } from '@kit.ArkUI';

/**
 * 沉浸光感（系统材质）运行时能力判定与材质工厂（API 26+）。
 *
 * 契约约束：
 * - uiMaterial 仅允许在本文件内访问（lazy import，首次访问才加载模块），
 *   其他文件一律经本文件的 isImmersiveSupported() 门控后再取材质对象。
 * - 版本短路先行：deviceInfo.sdkApiVersion >= 26 才触碰 uiMaterial，
 *   API 23~25 设备直接返回 false/undefined，零崩溃零回归。
 * - 判定结果与材质对象均为模块级缓存，进程生命周期内不变更参数（官方要求）。
 * - 返回 undefined 时调用方必须走既有样式分支。
 */

/** 沉浸光感所需最低 SDK API 版本 */
const IMMERSIVE_MIN_API: number = 26

let supportedCache: boolean | undefined = undefined
let tabBarCache: uiMaterial.ImmersiveMaterial | undefined = undefined

/** 设备是否支持沉浸式系统材质（双条件门控缓存结果，任何材质调用前必须经此判定） */
export function isImmersiveSupported(): boolean {
  if (supportedCache !== undefined) {
    return supportedCache
  }
  if (deviceInfo.sdkApiVersion < IMMERSIVE_MIN_API) {
    supportedCache = false
    return supportedCache
  }
  let result: boolean = false
  try {
    result = uiMaterial.isImmersiveMaterialSupported()
    console.info(`[MaterialUtils] sdkApiVersion=${deviceInfo.sdkApiVersion} isSupported=${result} ` +
      `materialLevel=${uiMaterial.getGlobalMaterialLevel()} materialState=${uiMaterial.getMaterialInfo().state}`)
  } catch (e) {
    // 低版本系统无 uiMaterial 实现时兜底降级
    result = false
  }
  supportedCache = result
  return result
}

/**
 * 首页底部悬浮页签胶囊材质（Tabs.barFloatingStyle.systemMaterial，API 26+）。
 * 官方典型场景同款默认参数（REGULAR 样式/透明赋色/带阴影）：折射、高光、边缘光效与深浅色自适应
 * 全部由系统按算力档位与用户沉浸光感设置接管，应用侧不调参。
 *
 * 红线：uiMaterial 的 systemMaterial 仅在"Navigation/NavDestination 标题栏"与
 * "横向 Tabs 的底部 TabBar"两处区域对普通容器组件生效，其余区域（如详情页 FAB/顶栏药丸/
 * 查看器底栏）设置后完全不渲染（透明），不要为那些区域创建材质——已踩坑回退。
 */
export function tabBarMaterial(): uiMaterial.ImmersiveMaterial | undefined {
  if (!isImmersiveSupported()) {
    return undefined
  }
  if (tabBarCache === undefined) {
    tabBarCache = new uiMaterial.ImmersiveMaterial({})
  }
  return tabBarCache
}
