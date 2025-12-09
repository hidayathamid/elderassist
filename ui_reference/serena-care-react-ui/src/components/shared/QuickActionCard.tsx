import { Card } from "@/components/ui/card";
import { cn } from "@/lib/utils";
import { LucideIcon } from "lucide-react";

interface QuickActionCardProps {
  icon: LucideIcon;
  title: string;
  subtitle?: string;
  onClick?: () => void;
  variant?: "default" | "primary" | "success" | "emergency";
  className?: string;
}

export const QuickActionCard = ({
  icon: Icon,
  title,
  subtitle,
  onClick,
  variant = "default",
  className,
}: QuickActionCardProps) => {
  const variants = {
    default: "bg-card border-border hover:border-primary/30",
    primary: "bg-primary-light border-primary/20 hover:border-primary/40",
    success: "bg-success-light border-success/20 hover:border-success/40",
    emergency: "bg-emergency-light border-emergency/20 hover:border-emergency/40",
  };

  const iconVariants = {
    default: "bg-muted text-foreground",
    primary: "bg-primary/10 text-primary",
    success: "bg-success/10 text-success",
    emergency: "bg-emergency/10 text-emergency",
  };

  return (
    <Card
      variant="action"
      padding="sm"
      onClick={onClick}
      className={cn(
        "flex flex-col items-center text-center min-w-[100px] cursor-pointer",
        variants[variant],
        className
      )}
    >
      <div className={cn(
        "w-12 h-12 rounded-xl flex items-center justify-center mb-2",
        iconVariants[variant]
      )}>
        <Icon className="h-6 w-6" />
      </div>
      <h4 className="font-semibold text-sm text-foreground">{title}</h4>
      {subtitle && (
        <p className="text-xs text-muted-foreground mt-0.5">{subtitle}</p>
      )}
    </Card>
  );
};
