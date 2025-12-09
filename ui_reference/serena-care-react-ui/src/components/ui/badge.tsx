import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";

import { cn } from "@/lib/utils";

const badgeVariants = cva(
  "inline-flex items-center rounded-full border px-3 py-1 text-xs font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2",
  {
    variants: {
      variant: {
        default: "border-transparent bg-primary text-primary-foreground",
        secondary: "border-transparent bg-secondary text-secondary-foreground",
        destructive: "border-transparent bg-destructive text-destructive-foreground",
        outline: "text-foreground border-border",
        success: "border-transparent bg-success text-success-foreground",
        emergency: "border-transparent bg-emergency text-emergency-foreground",
        warning: "border-transparent bg-warning text-warning-foreground",
        available: "border-transparent bg-success/10 text-success border-success/20",
        unavailable: "border-transparent bg-muted text-muted-foreground",
        scheduled: "border-transparent bg-primary/10 text-primary border-primary/20",
        completed: "border-transparent bg-success/10 text-success",
        cancelled: "border-transparent bg-emergency/10 text-emergency",
        pending: "border-transparent bg-warning/10 text-warning",
        premium: "border-transparent bg-gradient-to-r from-amber-400 to-orange-500 text-white",
        match: "border-transparent bg-primary/10 text-primary",
      },
    },
    defaultVariants: {
      variant: "default",
    },
  },
);

export interface BadgeProps extends React.HTMLAttributes<HTMLDivElement>, VariantProps<typeof badgeVariants> {}

function Badge({ className, variant, ...props }: BadgeProps) {
  return <div className={cn(badgeVariants({ variant }), className)} {...props} />;
}

export { Badge, badgeVariants };
