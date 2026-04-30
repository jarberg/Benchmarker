import * as React from "react";
import { cva } from "class-variance-authority";
import { cn } from "@/lib/utils";

const badgeVariants = cva(
  "inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-semibold uppercase tracking-wider",
  {
    variants: {
      tone: {
        pending:   "border-amber-500/40   bg-amber-500/15   text-amber-300",
        running:   "border-sky-500/40     bg-sky-500/15     text-sky-300",
        completed: "border-emerald-500/40 bg-emerald-500/15 text-emerald-300",
        failed:    "border-rose-500/40    bg-rose-500/15    text-rose-300",
        unreal:    "border-indigo-400/40  bg-indigo-400/10  text-indigo-300",
        unity:     "border-emerald-400/40 bg-emerald-400/10 text-emerald-300",
        generic:   "border-slate-500/40   bg-slate-500/10   text-slate-300"
      }
    },
    defaultVariants: { tone: "generic" }
  }
);

function Badge({ className, tone, ...props }) {
  return <div className={cn(badgeVariants({ tone }), className)} {...props} />;
}

export { Badge, badgeVariants };
