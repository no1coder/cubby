@testable import CubbyCore

/// 每种语言 2～4 段真实风格的代码片段（2～6 行）
enum CodeLanguageSamples {
    static let all: [CodeLanguageSample] = swift + javascript + python + json + shell + markup + sql + go + rust

    static let swift: [CodeLanguageSample] = [
        CodeLanguageSample(
            "SwiftUI 修饰符链（设计稿里的代码卡）", .swift,
            """
            Text("Ship it!")
                .font(.headline)
                .foregroundStyle(.purple)
            """),
        CodeLanguageSample(
            "SwiftUI 视图", .swift,
            """
            import SwiftUI

            struct CardView: View {
                @State private var count = 0
                var body: some View { Text("Ship it!").font(.headline) }
            }
            """),
        CodeLanguageSample(
            "guard 与 keypath", .swift,
            """
            guard let url = URL(string: path) else { return nil }
            let names = items.map(\\.name)
            """),
        CodeLanguageSample(
            "Swift 函数", .swift,
            """
            func greet(_ name: String) -> String {
                let message = "Hello, \\(name)"
                return message
            }
            """),
        CodeLanguageSample(
            "SwiftUI 布局", .swift,
            """
            VStack {
                Text("Hi")
                Spacer()
            }
            """),
    ]

    static let javascript: [CodeLanguageSample] = [
        CodeLanguageSample(
            "箭头函数", .javascript,
            """
            const add = (a, b) => a + b;
            console.log(add(1, 2));
            """),
        CodeLanguageSample(
            "TypeScript 接口", .javascript,
            """
            export interface User {
              name: string;
              age: number;
            }
            """),
        CodeLanguageSample(
            "function 与模板字符串", .javascript,
            """
            function greet(name) {
              return `Hello ${name}`;
            }
            """),
        CodeLanguageSample(
            "import from", .javascript,
            """
            import React from 'react';
            export default function App() {
              return null;
            }
            """),
    ]

    static let python: [CodeLanguageSample] = [
        CodeLanguageSample(
            "def 与 f-string", .python,
            """
            def greet(name):
                if not name:
                    return None
                return f"Hello {name}"
            """),
        CodeLanguageSample(
            "from import 与类", .python,
            """
            from pathlib import Path

            class Loader:
                def __init__(self, root):
                    self.root = Path(root)
            """),
        CodeLanguageSample(
            "elif", .python,
            """
            if score > 90:
                grade = "A"
            elif score > 80:
                grade = "B"
            """),
    ]

    static let json: [CodeLanguageSample] = [
        CodeLanguageSample(
            "对象", .json,
            """
            {
              "name": "Cubby",
              "version": 2,
              "tags": ["clipboard", "mac"]
            }
            """),
        CodeLanguageSample("对象数组", .json, #"[{"id": 1}, {"id": 2}]"#),
    ]

    static let shell: [CodeLanguageSample] = [
        CodeLanguageSample(
            "shebang 脚本", .shell,
            """
            #!/bin/bash
            set -euo pipefail
            echo "Building..."
            """),
        CodeLanguageSample(
            "常用命令", .shell,
            """
            brew install swift-format
            git status
            npm run build | grep error
            """),
        CodeLanguageSample(
            "提示符", .shell,
            """
            $ cd ~/code/cubby
            $ make test
            """),
        CodeLanguageSample(
            "环境变量", .shell,
            """
            export PATH="$HOME/bin:$PATH"
            source ~/.zshrc
            """),
    ]

    /// HTML 与 CSS
    static let markup: [CodeLanguageSample] = [
        CodeLanguageSample(
            "HTML 文档", .html,
            """
            <!DOCTYPE html>
            <html lang="en">
            <body><div class="card">Hello</div></body>
            </html>
            """),
        CodeLanguageSample(
            "HTML 片段", .html,
            """
            <div class="card">
              <p>Hello</p>
            </div>
            """),
        CodeLanguageSample(
            "CSS 规则", .css,
            """
            .card {
              padding: 12px;
              border-radius: 8px;
              color: #333;
            }
            """),
        CodeLanguageSample(
            "CSS 媒体查询", .css,
            """
            @media (max-width: 600px) {
              body { margin: 0; }
            }
            """),
    ]

    static let sql: [CodeLanguageSample] = [
        CodeLanguageSample(
            "SELECT", .sql,
            """
            SELECT id, name
            FROM users
            WHERE active = 1
            ORDER BY name;
            """),
        CodeLanguageSample(
            "小写 select", .sql,
            """
            select id, name from users
            where active = 1;
            """),
        CodeLanguageSample("INSERT", .sql, "INSERT INTO users (id, name) VALUES (1, 'Ada');"),
        CodeLanguageSample(
            "CREATE TABLE", .sql,
            """
            CREATE TABLE users (
              id INTEGER PRIMARY KEY,
              name TEXT NOT NULL
            );
            """),
        CodeLanguageSample("UPDATE", .sql, "UPDATE users SET name = 'Ada' WHERE id = 1;"),
    ]

    static let go: [CodeLanguageSample] = [
        CodeLanguageSample(
            "main 包", .go,
            """
            package main

            import "fmt"

            func main() {
                msg := "hello"
                fmt.Println(msg)
            }
            """),
        CodeLanguageSample(
            "方法与错误处理", .go,
            """
            func (s *Server) Start() error {
                if err := s.listen(); err != nil {
                    return err
                }
                return nil
            }
            """),
    ]

    static let rust: [CodeLanguageSample] = [
        CodeLanguageSample(
            "main", .rust,
            """
            fn main() {
                let mut count = 0;
                println!("{}", count);
            }
            """),
        CodeLanguageSample(
            "use 与 pub fn", .rust,
            """
            use std::collections::HashMap;

            pub fn build() -> HashMap<String, u32> {
                HashMap::new()
            }
            """),
        CodeLanguageSample(
            "impl", .rust,
            """
            impl Point {
                pub fn new(x: f64) -> Self { Self { x } }
            }
            """),
        CodeLanguageSample("带类型的常量", .rust, "const MAX: u32 = 10;"),
    ]
}
