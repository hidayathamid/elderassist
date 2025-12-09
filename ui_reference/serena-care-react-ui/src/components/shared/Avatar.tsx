import { cn } from "@/lib/utils";

interface AvatarProps {
  src?: string;
  name: string;
  size?: "xs" | "sm" | "md" | "lg" | "xl";
  showBorder?: boolean;
  status?: "online" | "offline" | "busy";
  className?: string;
}

const sizeClasses = {
  xs: "w-8 h-8",
  sm: "w-10 h-10",
  md: "w-12 h-12",
  lg: "w-16 h-16",
  xl: "w-20 h-20",
};

const statusColors = {
  online: "bg-success",
  offline: "bg-muted-foreground",
  busy: "bg-warning",
};

const getInitials = (name: string) => {
  return name
    .split(" ")
    .map((part) => part[0])
    .join("")
    .toUpperCase()
    .slice(0, 2);
};

export const Avatar = ({
  src,
  name,
  size = "md",
  showBorder = false,
  status,
  className,
}: AvatarProps) => {
  return (
    <div className={cn("relative inline-block", className)}>
      {src ? (
        <img
          src={src}
          alt={name}
          className={cn(
            "rounded-full object-cover",
            sizeClasses[size],
            showBorder && "border-2 border-primary/20"
          )}
        />
      ) : (
        <div
          className={cn(
            "rounded-full bg-primary/10 flex items-center justify-center font-semibold text-primary",
            sizeClasses[size],
            showBorder && "border-2 border-primary/20"
          )}
        >
          <span className={cn(
            size === "xs" && "text-xs",
            size === "sm" && "text-sm",
            size === "md" && "text-base",
            size === "lg" && "text-lg",
            size === "xl" && "text-xl",
          )}>
            {getInitials(name)}
          </span>
        </div>
      )}
      {status && (
        <span
          className={cn(
            "absolute bottom-0 right-0 rounded-full border-2 border-card",
            statusColors[status],
            size === "xs" && "w-2 h-2",
            size === "sm" && "w-2.5 h-2.5",
            size === "md" && "w-3 h-3",
            size === "lg" && "w-4 h-4",
            size === "xl" && "w-5 h-5",
          )}
        />
      )}
    </div>
  );
};
