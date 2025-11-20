/// Type system models for SpacetimeDB schema

class TypeSpace {
  final List<AlgebraicType> types;

  TypeSpace({required this.types});

  factory TypeSpace.fromJson(Map<String, dynamic> json) {
    final typesJson = json['types'];

    return TypeSpace(
      types: typesJson is List
          ? typesJson.map((t) => AlgebraicType.fromJson(t)).toList()
          : [],
    );
  }
}

class AlgebraicType {
  final ProductType? product;

  AlgebraicType({this.product});

  factory AlgebraicType.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('Product')) {
      return AlgebraicType(product: ProductType.fromJson(json['Product']));
    }
    // For now, only handle Product types
    return AlgebraicType();
  }
}

class ProductType {
  final List<ProductElement> elements;
  ProductType({required this.elements});
  factory ProductType.fromJson(Map<String, dynamic> json) {
    final elementsJson = json['elements'];

    return ProductType(
      elements: elementsJson is List
          ? elementsJson.map((e) => ProductElement.fromJson(e)).toList()
          : [],
    );
  }
}

class ProductElement {
  final String? name;
  final Map<String, dynamic> algebraicType;

  ProductElement({this.name, required this.algebraicType});

  factory ProductElement.fromJson(Map<String, dynamic> json) {
    final nameObj = json['name'];
    final fieldName = nameObj['some'] ?? "";

    return ProductElement(
      name: fieldName,
      algebraicType: json['algebraic_type'] ?? {},
    );
  }
}

class TypeDef {
  final List<String> scope;
  final String name;
  final int typeRef;
  final bool customOrdering;

  TypeDef({
    required this.scope,
    required this.name,
    required this.typeRef,
    required this.customOrdering,
  });

  factory TypeDef.fromJson(Map<String, dynamic> json) {
    final nameJson = json['name'];
    final typeName = nameJson['name'] ?? "";
    final scopeJson =  nameJson['scope'] ?? "";
    final scopeList = scopeJson is List
        ? scopeJson.map((s) => s.toString()).toList()
        : <String>[];

    return TypeDef(
      scope: scopeList,
      name: typeName,
      typeRef: json['ty'] ?? 0,
      customOrdering: json['custom_ordering'] ?? false,
    );
  }
}
