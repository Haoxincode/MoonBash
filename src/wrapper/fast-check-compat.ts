import baseFc from "fast-check-real";

type StringOfConstraints = {
  minLength?: number;
  maxLength?: number;
};

type FastCheckWithCompat = typeof baseFc & {
  stringOf?: (
    arbitrary: ReturnType<typeof baseFc.constantFrom<string>>,
    constraints?: StringOfConstraints,
  ) => ReturnType<typeof baseFc.string>;
};

const stringOfCompat: NonNullable<FastCheckWithCompat["stringOf"]> = (
  arbitrary,
  constraints = {},
) => {
  const minLength = constraints.minLength ?? 0;
  const maxLength =
    typeof constraints.maxLength === "number"
      ? constraints.maxLength
      : Math.max(minLength, 32);
  return baseFc
    .array(arbitrary, { minLength, maxLength })
    .map((items) => items.join(""));
};

const compat = new Proxy(baseFc as FastCheckWithCompat, {
  get(target, prop, receiver) {
    if (prop === "stringOf") {
      return typeof target.stringOf === "function" ? target.stringOf : stringOfCompat;
    }
    const value = Reflect.get(target, prop, receiver);
    if (typeof value === "function") {
      return value.bind(target);
    }
    return value;
  },
});

export default compat as typeof baseFc & {
  stringOf: NonNullable<FastCheckWithCompat["stringOf"]>;
};
