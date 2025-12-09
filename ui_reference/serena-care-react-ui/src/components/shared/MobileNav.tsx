import { cn } from "@/lib/utils";
import { NavLink } from "@/components/NavLink";
import { Home, Calendar, Activity, User, Briefcase, MessageCircle, AlertTriangle } from "lucide-react";

interface NavItem {
  icon: React.ElementType;
  label: string;
  path: string;
  isCenter?: boolean;
}

interface MobileNavProps {
  items: NavItem[];
  centerButton?: {
    icon: React.ElementType;
    label: string;
    onClick: () => void;
    variant?: "sos" | "default";
  };
  basePath: string;
}

export const MobileNav = ({ items, centerButton, basePath }: MobileNavProps) => {
  const leftItems = items.slice(0, 2);
  const rightItems = items.slice(2, 4);

  return (
    <nav className="fixed bottom-0 left-0 right-0 bg-card border-t border-border shadow-bottom-nav z-50">
      <div className="flex items-center justify-around h-18 px-2 max-w-md mx-auto">
        {/* Left items */}
        {leftItems.map((item) => (
          <NavLink
            key={item.path}
            to={`${basePath}${item.path}`}
            className="flex flex-col items-center justify-center py-2 px-4 text-muted-foreground transition-colors"
            activeClassName="text-primary"
          >
            <item.icon className="h-6 w-6 mb-1" />
            <span className="text-xs font-medium">{item.label}</span>
          </NavLink>
        ))}

        {/* Center SOS/Action Button */}
        {centerButton && (
          <button
            onClick={centerButton.onClick}
            className={cn(
              "flex flex-col items-center justify-center -mt-6 transition-transform hover:scale-105",
              centerButton.variant === "sos" && "relative"
            )}
          >
            {centerButton.variant === "sos" ? (
              <>
                <div className="absolute inset-0 bg-emergency/20 rounded-full animate-pulse-ring" />
                <div className="relative h-16 w-16 bg-emergency rounded-full flex items-center justify-center shadow-float">
                  <centerButton.icon className="h-8 w-8 text-emergency-foreground" />
                </div>
                <span className="text-xs font-bold text-emergency mt-1">{centerButton.label}</span>
              </>
            ) : (
              <div className="h-14 w-14 bg-primary rounded-full flex items-center justify-center shadow-float">
                <centerButton.icon className="h-7 w-7 text-primary-foreground" />
              </div>
            )}
          </button>
        )}

        {/* Right items */}
        {rightItems.map((item) => (
          <NavLink
            key={item.path}
            to={`${basePath}${item.path}`}
            className="flex flex-col items-center justify-center py-2 px-4 text-muted-foreground transition-colors"
            activeClassName="text-primary"
          >
            <item.icon className="h-6 w-6 mb-1" />
            <span className="text-xs font-medium">{item.label}</span>
          </NavLink>
        ))}
      </div>
    </nav>
  );
};

// Client Navigation
export const ClientNav = ({ onSOS }: { onSOS: () => void }) => {
  const items: NavItem[] = [
    { icon: Home, label: "Home", path: "" },
    { icon: Calendar, label: "Book", path: "/book" },
    { icon: Activity, label: "Activity", path: "/activity" },
    { icon: User, label: "Account", path: "/profile" },
  ];

  return (
    <MobileNav
      items={items}
      centerButton={{
        icon: AlertTriangle,
        label: "SOS",
        onClick: onSOS,
        variant: "sos",
      }}
      basePath="/client"
    />
  );
};

// Caregiver Navigation
export const CaregiverNav = () => {
  const items: NavItem[] = [
    { icon: Home, label: "Home", path: "" },
    { icon: Briefcase, label: "Jobs", path: "/jobs" },
    { icon: AlertTriangle, label: "SOS", path: "/sos-alerts" },
    { icon: MessageCircle, label: "Chat", path: "/chat" },
    { icon: User, label: "Profile", path: "/profile" },
  ];

  return (
    <nav className="fixed bottom-0 left-0 right-0 bg-card border-t border-border shadow-bottom-nav z-50">
      <div className="flex items-center justify-around h-18 px-2 max-w-md mx-auto">
        {items.map((item) => (
          <NavLink
            key={item.path}
            to={`/caregiver${item.path}`}
            className="flex flex-col items-center justify-center py-2 px-3 text-muted-foreground transition-colors"
            activeClassName="text-primary"
          >
            <item.icon className={cn(
              "h-6 w-6 mb-1",
              item.label === "SOS" && "text-emergency"
            )} />
            <span className={cn(
              "text-xs font-medium",
              item.label === "SOS" && "text-emergency"
            )}>{item.label}</span>
          </NavLink>
        ))}
      </div>
    </nav>
  );
};
