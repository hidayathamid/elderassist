import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Star, MapPin, Clock } from "lucide-react";
import { cn } from "@/lib/utils";

interface CaregiverCardProps {
  id: string;
  name: string;
  photo: string;
  rating: number;
  specialization: string;
  distance?: string;
  available?: boolean;
  price?: string;
  eta?: string;
  isMatch?: boolean;
  onBook?: () => void;
  variant?: "horizontal" | "vertical" | "detailed";
  className?: string;
}

export const CaregiverCard = ({
  id,
  name,
  photo,
  rating,
  specialization,
  distance,
  available = true,
  price,
  eta,
  isMatch,
  onBook,
  variant = "vertical",
  className,
}: CaregiverCardProps) => {
  if (variant === "horizontal") {
    return (
      <Card
        variant="caregiver"
        padding="none"
        className={cn("flex items-center gap-4 p-3 min-w-[280px]", className)}
      >
        <img
          src={photo}
          alt={name}
          className="w-16 h-16 rounded-xl object-cover"
        />
        <div className="flex-1 min-w-0">
          <h4 className="font-semibold text-foreground truncate">{name}</h4>
          <p className="text-sm text-muted-foreground truncate">{specialization}</p>
          <div className="flex items-center gap-2 mt-1">
            <Star className="h-4 w-4 text-warning fill-warning" />
            <span className="text-sm font-medium">{rating}</span>
            {distance && (
              <>
                <span className="text-muted-foreground">•</span>
                <MapPin className="h-3 w-3 text-muted-foreground" />
                <span className="text-sm text-muted-foreground">{distance}</span>
              </>
            )}
          </div>
        </div>
        {available && (
          <Badge variant="available" className="shrink-0">Available</Badge>
        )}
      </Card>
    );
  }

  if (variant === "detailed") {
    return (
      <Card
        variant="caregiver"
        padding="none"
        className={cn("p-4", className)}
      >
        <div className="flex gap-4">
          <img
            src={photo}
            alt={name}
            className="w-20 h-20 rounded-xl object-cover"
          />
          <div className="flex-1">
            <div className="flex items-start justify-between">
              <div>
                <h4 className="font-semibold text-lg text-foreground">{name}</h4>
                <p className="text-sm text-muted-foreground">{specialization}</p>
              </div>
              {isMatch && <Badge variant="match">Service Match</Badge>}
            </div>
            <div className="flex items-center gap-4 mt-2">
              <div className="flex items-center gap-1">
                <Star className="h-4 w-4 text-warning fill-warning" />
                <span className="text-sm font-medium">{rating}</span>
              </div>
              {eta && (
                <div className="flex items-center gap-1 text-sm text-muted-foreground">
                  <Clock className="h-4 w-4" />
                  <span>{eta}</span>
                </div>
              )}
              {distance && (
                <div className="flex items-center gap-1 text-sm text-muted-foreground">
                  <MapPin className="h-4 w-4" />
                  <span>{distance}</span>
                </div>
              )}
            </div>
            {price && (
              <p className="text-lg font-bold text-primary mt-2">{price}</p>
            )}
          </div>
        </div>
        {onBook && (
          <Button onClick={onBook} className="w-full mt-4" size="lg">
            Book Now
          </Button>
        )}
      </Card>
    );
  }

  // Default vertical card (Foodpanda style)
  return (
    <Card
      variant="action"
      padding="none"
      className={cn("w-[160px] shrink-0 overflow-hidden", className)}
    >
      <div className="relative">
        <img
          src={photo}
          alt={name}
          className="w-full h-28 object-cover"
        />
        {available && (
          <Badge variant="available" className="absolute top-2 right-2 text-[10px] px-2">
            Available Now
          </Badge>
        )}
        {isMatch && (
          <Badge variant="match" className="absolute top-2 left-2 text-[10px] px-2">
            Match
          </Badge>
        )}
      </div>
      <div className="p-3">
        <h4 className="font-semibold text-foreground truncate">{name}</h4>
        <p className="text-xs text-muted-foreground truncate">{specialization}</p>
        <div className="flex items-center justify-between mt-2">
          <div className="flex items-center gap-1">
            <Star className="h-3 w-3 text-warning fill-warning" />
            <span className="text-xs font-medium">{rating}</span>
          </div>
          {distance && (
            <span className="text-xs text-muted-foreground">{distance}</span>
          )}
        </div>
        {onBook && (
          <Button
            variant="cardAction"
            size="sm"
            onClick={onBook}
            className="w-full mt-2 text-xs"
          >
            Book Again
          </Button>
        )}
      </div>
    </Card>
  );
};
