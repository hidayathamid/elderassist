import { Bell, ChevronLeft } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { useNavigate } from "react-router-dom";
import { cn } from "@/lib/utils";

interface HeaderProps {
  title?: string;
  greeting?: string;
  subtitle?: string;
  showBack?: boolean;
  showNotification?: boolean;
  notificationCount?: number;
  avatar?: string;
  rightContent?: React.ReactNode;
  className?: string;
}

export const Header = ({
  title,
  greeting,
  subtitle,
  showBack,
  showNotification = true,
  notificationCount = 0,
  avatar,
  rightContent,
  className,
}: HeaderProps) => {
  const navigate = useNavigate();

  return (
    <header className={cn(
      "sticky top-0 z-40 bg-background/80 backdrop-blur-lg border-b border-border/50",
      className
    )}>
      <div className="flex items-center justify-between h-16 px-4">
        <div className="flex items-center gap-3">
          {showBack && (
            <Button
              variant="ghost"
              size="icon"
              onClick={() => navigate(-1)}
              className="shrink-0"
            >
              <ChevronLeft className="h-6 w-6" />
            </Button>
          )}
          
          {avatar && (
            <img
              src={avatar}
              alt="Profile"
              className="w-10 h-10 rounded-full object-cover border-2 border-primary/20"
            />
          )}
          
          <div>
            {greeting && (
              <>
                <p className="text-sm text-muted-foreground">{greeting}</p>
                <h1 className="text-lg font-bold text-foreground">{subtitle}</h1>
              </>
            )}
            {title && !greeting && (
              <h1 className="text-lg font-bold text-foreground">{title}</h1>
            )}
          </div>
        </div>

        <div className="flex items-center gap-2">
          {rightContent}
          
          {showNotification && (
            <Button variant="ghost" size="icon" className="relative">
              <Bell className="h-6 w-6" />
              {notificationCount > 0 && (
                <Badge
                  variant="emergency"
                  className="absolute -top-1 -right-1 h-5 w-5 p-0 flex items-center justify-center text-[10px]"
                >
                  {notificationCount}
                </Badge>
              )}
            </Button>
          )}
        </div>
      </div>
    </header>
  );
};
