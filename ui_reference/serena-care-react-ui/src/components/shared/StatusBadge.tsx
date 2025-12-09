import { Badge, BadgeProps } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

type Status = 
  | "available"
  | "unavailable" 
  | "scheduled"
  | "in-progress"
  | "completed"
  | "cancelled"
  | "pending"
  | "online"
  | "offline"
  | "busy";

interface StatusBadgeProps extends Omit<BadgeProps, "variant"> {
  status: Status;
  showDot?: boolean;
}

const statusConfig: Record<Status, { variant: BadgeProps["variant"]; label: string; dotColor: string }> = {
  available: { variant: "available", label: "Available", dotColor: "bg-success" },
  unavailable: { variant: "unavailable", label: "Unavailable", dotColor: "bg-muted-foreground" },
  scheduled: { variant: "scheduled", label: "Scheduled", dotColor: "bg-primary" },
  "in-progress": { variant: "warning", label: "In Progress", dotColor: "bg-warning" },
  completed: { variant: "completed", label: "Completed", dotColor: "bg-success" },
  cancelled: { variant: "cancelled", label: "Cancelled", dotColor: "bg-emergency" },
  pending: { variant: "pending", label: "Pending", dotColor: "bg-warning" },
  online: { variant: "available", label: "Online", dotColor: "bg-success" },
  offline: { variant: "unavailable", label: "Offline", dotColor: "bg-muted-foreground" },
  busy: { variant: "warning", label: "Busy", dotColor: "bg-warning" },
};

export const StatusBadge = ({ status, showDot = true, className, ...props }: StatusBadgeProps) => {
  const config = statusConfig[status];

  return (
    <Badge variant={config.variant} className={cn("gap-1.5", className)} {...props}>
      {showDot && (
        <span className={cn("w-2 h-2 rounded-full", config.dotColor)} />
      )}
      {config.label}
    </Badge>
  );
};
