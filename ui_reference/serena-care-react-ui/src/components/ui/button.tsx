import * as React from "react";
import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";

import { cn } from "@/lib/utils";

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap text-base font-semibold ring-offset-background transition-all duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50 [&_svg]:pointer-events-none [&_svg]:size-5 [&_svg]:shrink-0 active:scale-[0.98]",
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground hover:bg-primary/90 shadow-card rounded-lg",
        destructive: "bg-destructive text-destructive-foreground hover:bg-destructive/90 shadow-card rounded-lg",
        outline: "border-2 border-border bg-background hover:bg-muted hover:border-primary/30 rounded-lg",
        secondary: "bg-secondary text-secondary-foreground hover:bg-secondary/80 rounded-lg",
        ghost: "hover:bg-accent hover:text-accent-foreground rounded-lg",
        link: "text-primary underline-offset-4 hover:underline",
        emergency: "bg-emergency text-emergency-foreground hover:bg-emergency/90 shadow-card rounded-lg",
        success: "bg-success text-success-foreground hover:bg-success/90 shadow-card rounded-lg",
        fab: "bg-primary text-primary-foreground shadow-float hover:shadow-xl rounded-full",
        sos: "bg-emergency text-emergency-foreground shadow-float rounded-full aspect-square hover:scale-105",
        cardAction: "bg-primary/10 text-primary hover:bg-primary hover:text-primary-foreground rounded-lg",
        elderly: "bg-primary text-primary-foreground text-lg py-4 px-8 shadow-card hover:bg-primary/90 rounded-xl",
      },
      size: {
        default: "h-12 px-6 py-3",
        sm: "h-10 rounded-md px-4 text-sm",
        lg: "h-14 rounded-xl px-8 text-lg",
        xl: "h-16 rounded-xl px-10 text-xl",
        icon: "h-12 w-12",
        iconSm: "h-10 w-10",
        iconLg: "h-14 w-14",
        sosLg: "h-20 w-20",
        sosXl: "h-24 w-24",
        full: "h-14 w-full rounded-xl px-6",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  },
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean;
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild = false, ...props }, ref) => {
    const Comp = asChild ? Slot : "button";
    return <Comp className={cn(buttonVariants({ variant, size, className }))} ref={ref} {...props} />;
  },
);
Button.displayName = "Button";

export { Button, buttonVariants };
