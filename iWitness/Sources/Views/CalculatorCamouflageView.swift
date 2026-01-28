import SwiftUI

/// Calculator Camouflage View
/// Looks like a normal calculator but reveals OnTheRecord when PIN is entered
struct CalculatorCamouflageView: View {
    @Binding var isUnlocked: Bool
    
    @State private var displayText = "0"
    @State private var currentOperation: Operation? = nil
    @State private var previousValue: Double = 0
    @State private var shouldResetDisplay = false
    @State private var enteredSequence = ""
    
    @State private var shakeOffset: CGFloat = 0
    @State private var backgroundColor = Color(uiColor: .systemBackground)
    
    private let storedPIN: String
    
    enum Operation {
        case add, subtract, multiply, divide
    }
    
    init(isUnlocked: Binding<Bool>) {
        self._isUnlocked = isUnlocked
        self.storedPIN = UserDefaults.standard.string(forKey: "safe_pin") ?? "1234"
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                Spacer()
                
                // Display
                HStack {
                    Spacer()
                    Text(displayText)
                        .font(.system(size: 72, weight: .light, design: .default))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                        .padding(.horizontal, 24)
                }
                .frame(height: 100)
                .offset(x: shakeOffset)
                
                // Button grid
                VStack(spacing: 12) {
                    // Row 1: AC, +/-, %, ÷
                    HStack(spacing: 12) {
                        calcButton("AC", style: .function) { clearAll() }
                        calcButton("±", style: .function) { toggleSign() }
                        calcButton("%", style: .function) { percentage() }
                        calcButton("÷", style: .operation) { setOperation(.divide) }
                    }
                    
                    // Row 2: 7, 8, 9, ×
                    HStack(spacing: 12) {
                        calcButton("7", style: .number) { appendDigit("7") }
                        calcButton("8", style: .number) { appendDigit("8") }
                        calcButton("9", style: .number) { appendDigit("9") }
                        calcButton("×", style: .operation) { setOperation(.multiply) }
                    }
                    
                    // Row 3: 4, 5, 6, -
                    HStack(spacing: 12) {
                        calcButton("4", style: .number) { appendDigit("4") }
                        calcButton("5", style: .number) { appendDigit("5") }
                        calcButton("6", style: .number) { appendDigit("6") }
                        calcButton("-", style: .operation) { setOperation(.subtract) }
                    }
                    
                    // Row 4: 1, 2, 3, +
                    HStack(spacing: 12) {
                        calcButton("1", style: .number) { appendDigit("1") }
                        calcButton("2", style: .number) { appendDigit("2") }
                        calcButton("3", style: .number) { appendDigit("3") }
                        calcButton("+", style: .operation) { setOperation(.add) }
                    }
                    
                    // Row 5: 0 (wide), ., =
                    HStack(spacing: 12) {
                        calcButton("0", style: .number, isWide: true) { appendDigit("0") }
                        calcButton(".", style: .number) { appendDecimal() }
                        calcButton("=", style: .operation) { calculateResult() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, geometry.safeAreaInsets.bottom + 16)
            }
        }
        .background(backgroundColor.ignoresSafeArea())
    }
    
    // MARK: - Button Styles
    
    enum ButtonStyle {
        case number
        case operation
        case function
    }
    
    private func calcButton(_ title: String, style: ButtonStyle, isWide: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()
        }) {
            Text(title)
                .font(.system(size: 32, weight: .medium))
                .foregroundColor(style == .operation ? .white : (style == .function ? .black : .white))
                .frame(width: isWide ? 170 : 80, height: 80)
                .background(buttonColor(for: style))
                .clipShape(RoundedRectangle(cornerRadius: isWide ? 40 : 40))
        }
    }
    
    private func buttonColor(for style: ButtonStyle) -> Color {
        switch style {
        case .number:
            return Color(uiColor: UIColor.darkGray)
        case .operation:
            return .orange
        case .function:
            return Color(uiColor: UIColor.lightGray)
        }
    }
    
    // MARK: - Calculator Logic
    
    private func appendDigit(_ digit: String) {
        // Track sequence for PIN check
        enteredSequence += digit
        
        if shouldResetDisplay || displayText == "0" {
            displayText = digit
            shouldResetDisplay = false
        } else {
            displayText += digit
        }
    }
    
    private func appendDecimal() {
        if !displayText.contains(".") {
            displayText += "."
        }
    }
    
    private func clearAll() {
        displayText = "0"
        previousValue = 0
        currentOperation = nil
        shouldResetDisplay = false
        enteredSequence = ""
    }
    
    private func toggleSign() {
        if let value = Double(displayText) {
            displayText = formatNumber(-value)
        }
    }
    
    private func percentage() {
        if let value = Double(displayText) {
            displayText = formatNumber(value / 100)
        }
    }
    
    private func setOperation(_ op: Operation) {
        if let currentValue = Double(displayText) {
            previousValue = currentValue
        }
        currentOperation = op
        shouldResetDisplay = true
    }
    
    private func calculateResult() {
        // Check if entered sequence matches PIN
        if enteredSequence == storedPIN || displayText == storedPIN {
            // Success! Unlock the app
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            withAnimation(.easeInOut(duration: 0.3)) {
                isUnlocked = true
            }
            return
        }
        
        // Normal calculator behavior
        guard let operation = currentOperation,
              let currentValue = Double(displayText) else {
            return
        }
        
        var result: Double
        switch operation {
        case .add:
            result = previousValue + currentValue
        case .subtract:
            result = previousValue - currentValue
        case .multiply:
            result = previousValue * currentValue
        case .divide:
            result = currentValue != 0 ? previousValue / currentValue : 0
        }
        
        displayText = formatNumber(result)
        previousValue = result
        currentOperation = nil
        shouldResetDisplay = true
        enteredSequence = ""
    }
    
    private func formatNumber(_ number: Double) -> String {
        if number.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", number)
        } else {
            return String(format: "%.8g", number)
        }
    }
}

// MARK: - Preview

#Preview {
    CalculatorCamouflageView(isUnlocked: .constant(false))
}
