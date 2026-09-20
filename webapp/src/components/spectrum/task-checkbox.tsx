// Adapted from Spectrum UI TaskCheckbox, Apache-2.0.
// Kept controlled semantics, spring feedback, check drawing and reduced motion.
// Removed task text, strikethrough and confetti for compact mail selection.
import { motion, useReducedMotion } from "framer-motion";
const MICRO_SPRING = { type: "spring", stiffness: 500, damping: 30 } as const;
const CHECK_PATH = "M5 12.5L10 17.5L19 7.5";
export function TaskCheckbox({
  checked,
  onCheckedChange,
  label,
}: {
  checked: boolean;
  onCheckedChange: (next: boolean) => void;
  label: string;
}) {
  const reduce = useReducedMotion();
  return (
    <motion.button
      type="button"
      role="checkbox"
      aria-checked={checked}
      aria-label={label}
      className="selection"
      onClick={() => onCheckedChange(!checked)}
      whileTap={reduce ? undefined : { scale: 0.9 }}
      transition={MICRO_SPRING}
    >
      <svg
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="3"
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden="true"
      >
        <motion.path
          d={CHECK_PATH}
          initial={false}
          animate={{ pathLength: checked ? 1 : 0, opacity: checked ? 1 : 0 }}
          transition={
            reduce
              ? { duration: 0 }
              : checked
                ? {
                    pathLength: { delay: 0.06, duration: 0.2, ease: "easeOut" },
                    opacity: { delay: 0.06, duration: 0.01 },
                  }
                : { duration: 0.1 }
          }
        />
      </svg>
    </motion.button>
  );
}
