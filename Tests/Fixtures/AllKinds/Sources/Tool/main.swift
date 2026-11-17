import AllKinds

let square = Square(side: 2)
print(square.area)

func report(_ value: Double) {
    print("value: \(value)")
}

report(square.perimeter)
