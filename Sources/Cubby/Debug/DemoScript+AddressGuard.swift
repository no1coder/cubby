#if DEBUG
import AppKit
import CubbyCore
import SwiftUI

/// `demo:address-guard`：在虚构的充值页点「Copy」复制地址 → 0.4 秒后剪贴板被换成首尾相同的另一个地址 →
/// 地址守护的状态机判定为替换，弹出红色警示卡。剪贴板变化只是喂给 AddressGuardController 的事件，
/// 不读写真实剪贴板，也不启动输入监控
extension AppDelegate {
    func runAddressGuardDemo() async {
        guard let addressGuard else { return }
        // 相当于「输入监控已授权」：时间窗按看得到 ⌘C 的配置
        addressGuard.syncConfiguration(monitorsKeystrokes: true)
        let page = DemoDepositPage(address: SecurityDemo.original.value)
        let window = DemoWindows.documentWindow(
            title: "Wallet - Deposit", frame: DemoWindows.appKitFrame(topLeft: Self.depositFrame))
        window.contentView = NSHostingView(rootView: DemoDepositView(page: page))
        window.orderFrontRegardless()
        let button = CGPoint(x: Self.depositFrame.maxX - 84, y: Self.depositFrame.minY + 151)
        let cursor = DemoCursor(at: DemoWindows.appKitPoint(CGPoint(x: button.x - 300, y: button.y + 120)))
        await DemoClock.pause(0.6)
        await cursor.move(to: DemoWindows.appKitPoint(button), duration: 0.9)
        await DemoClock.pause(0.2)
        await cursor.click()
        page.copied = true
        addressGuard.copyKeystroke()
        addressGuard.pasteboardChanged(text: SecurityDemo.original.value, source: SecurityDemo.safari)
        await DemoClock.pause(0.45)
        // 后台程序换掉了剪贴板（前台仍是浏览器）
        addressGuard.pasteboardChanged(text: Self.replacementAddress, source: SecurityDemo.safari)
        await DemoClock.pause(0.6)
        await cursor.move(to: DemoWindows.appKitPoint(CGPoint(x: 1360, y: 300)), duration: 0.8)
        await DemoClock.pause(4.0)
    }

    /// 替换进来的地址：首尾 4 位与原地址相同，并且是合法的 EIP-55 校验大小写（否则识别不出是地址，状态机不会判定为替换）
    private static let replacementAddress = "0x5aAeE58b081006F7E3dFC967A64CB14028d5eAed"

    /// 充值页窗口（屏幕左上原点，点）
    private static let depositFrame = CGRect(x: 880, y: 470, width: 800, height: 290)
}

@Observable
@MainActor
private final class DemoDepositPage {
    let address: String
    var copied = false

    init(address: String) {
        self.address = address
    }
}

/// 虚构的钱包充值页
private struct DemoDepositView: View {
    let page: DemoDepositPage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.indigo)
                Text(verbatim: "Deposit ETH")
                    .font(.system(size: 20, weight: .semibold))
            }
            Text(verbatim: "Your deposit address (Ethereum network)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            HStack {
                Text(verbatim: page.address)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 12)
                Label {
                    Text(verbatim: page.copied ? "Copied" : "Copy")
                } icon: {
                    Image(systemName: page.copied ? "checkmark" : "doc.on.doc")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(page.copied ? Color.green : Color.accentColor))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary))
            Text(verbatim: "Only send ETH and ERC-20 tokens to this address.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
#endif
