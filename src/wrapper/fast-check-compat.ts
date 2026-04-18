import baseFc from "fast-check-real";
import type { Arbitrary } from "fast-check";

type StringOfConstraints = {
  minLength?: number;
  maxLength?: number;
};

type FastCheckStringOf = <T extends string>(
  arbitrary: Arbitrary<T>,
  constraints?: StringOfConstraints,
) => Arbitrary<string>;

type FastCheckWithCompat = typeof baseFc & {
  stringOf?: FastCheckStringOf;
};

const stringOfCompat: FastCheckStringOf = <T extends string>(
  arbitrary: Arbitrary<T>,
  constraints: StringOfConstraints = {},
) => {
  const minLength = constraints.minLength ?? 0;
  const maxLength =
    typeof constraints.maxLength === "number" ? constraints.maxLength : Math.max(minLength, 32);
  return baseFc.array(arbitrary, { minLength, maxLength }).map((items: T[]) => items.join(""));
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
